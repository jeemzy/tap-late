import AVKit
import Observation
import Translation
import TapLateCore

enum LiveTranslationPhase { case idle, checking, picker, starting, readyToOpen, opening, live, stopping }

struct FloatingWindowReadiness {
    let frameEnqueued: Bool
    let frameDisplayable: Bool
    let previewVisible: Bool
    let foregroundActive: Bool
    let pipPossible: Bool

    var canOpen: Bool {
        frameEnqueued && frameDisplayable && previewVisible && foregroundActive && pipPossible
    }
}

#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif

@MainActor @Observable final class LiveTranslation: NSObject, AVPictureInPictureControllerDelegate,
    AVPictureInPictureSampleBufferPlaybackDelegate {
    private(set) var phase: LiveTranslationPhase = .idle
    private(set) var message: String?
    let display = AVSampleBufferDisplayLayer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    @ObservationIgnored private lazy var receiver = synchronizer.sampleBufferReceiver(adding: display.sampleBufferRenderer)

    private(set) var framesPresented = 0
    @ObservationIgnored private var stage = ""
    @ObservationIgnored private var startSnapshot: String?
    @ObservationIgnored private var sessionID: UUID?
    #if canImport(ScreenCaptureKit)
    @ObservationIgnored private var capture: LiveCapture?
    @ObservationIgnored private var stream: SCStream?
    #elseif DEBUG && targetEnvironment(simulator)
    @ObservationIgnored private var fixtureTask: Task<Void, Never>?
    private(set) var sampleDescription = ""
    private(set) var backgroundPages: Set<Int> = []
    #endif
    @ObservationIgnored private var pip: AVPictureInPictureController?
    @ObservationIgnored private var startTimeout: Task<Void, Never>?
    @ObservationIgnored private var processing: Task<Void, Never>?
    @ObservationIgnored private var pendingNearbyFrame: SampledLiveFrame?
    @ObservationIgnored private var sequence = LiveFrameSequence()
    @ObservationIgnored private var cache: [String: RegionTranslation] = [:]
    @ObservationIgnored private var movingScope = false
    @ObservationIgnored private var area: NearbyArea?
    @ObservationIgnored private var lastScreen: CGSize?
    @ObservationIgnored private var lastOrientation: CGImagePropertyOrientation?
    @ObservationIgnored private var trackingInterrupted = false
    @ObservationIgnored private var preference = ApplePreference.fast
    @ObservationIgnored private var audioActive = false

    override init() {
        super.init()
        display.preventsCapture = supportedCaptureProtection
        display.videoGravity = .resizeAspect
        synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        synchronizer.setRate(1, time: now, atHostTime: now)
    }

    private var supportedCaptureProtection: Bool {
        #if DEBUG && targetEnvironment(simulator)
        AVPictureInPictureController.isPictureInPictureSupported()
        #else
        true
        #endif
    }

    func start(scope: LiveReadingScope, engine: ApplePreference) async {
        guard phase == .idle else { return }
        message = nil
        framesPresented = 0
        movingScope = scope == .near
        display.preventsCapture = !movingScope && supportedCaptureProtection
        area = nil
        trackingInterrupted = false
        lastScreen = nil
        lastOrientation = nil
        startSnapshot = nil
        stage = "PiP availability"
        let supported = AVPictureInPictureController.isPictureInPictureSupported()
        #if canImport(ScreenCaptureKit)
        guard supported else {
            message = "Picture in Picture is unavailable on this device."
            return
        }
        sessionID = UUID()
        let observer = LiveCapture(owner: self, scope: scope)
        capture = observer
        preference = engine
        phase = .checking
        let readiness = await engine.readiness()
        guard capture === observer else { return }
        guard readiness == .installed else {
            stop(readiness == .supported ? "Prepare the Chinese and English languages to start live translation."
                 : "This engine is unavailable for Chinese to English.")
            return
        }
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        picker.add(observer)
        picker.isActive = true
        phase = .picker
        stage = "Screen-sharing picker"
        picker.present()
        #elseif DEBUG && targetEnvironment(simulator)
        let id = UUID()
        sessionID = id
        preference = engine
        backgroundPages.removeAll()
        phase = .starting
        if supported {
            do { try prepareWindow() }
            catch { failed(error); return }
        } else {
            message = "PiP unavailable on this simulator. Showing the sample frames inline."
        }
        let sampler = LiveFrameSampler(scope: scope)
        fixtureTask = Task {
            var page = 0
            while !Task.isCancelled, sessionID == id {
                guard let sample = LiveSamplePages.sample(page, movingScope: movingScope),
                      let frame = sample.withUnsafeSampleBuffer({ sampler.frame($0, orientation: .up) }) else {
                    stop("Could not prepare the simulator sample page.")
                    return
                }
                receive(frame, session: id)
                if sessionID == id {
                    switch frame {
                    case .locating: break
                    case .content(let content):
                        let target = page == 0 ? "Camera" : "Tripod"
                        if let edge = content.area?.edge {
                            sampleDescription = "\(target) · reading \(edge == .above ? "above" : "below")"
                        } else {
                            sampleDescription = "\(target) · \(content.image.width) × \(content.image.height)"
                        }
                    }
                    if pip?.isPictureInPictureActive == true, UIApplication.shared.applicationState == .background {
                        backgroundPages.insert(page)
                    }
                }
                page = 1 - page
                try? await Task.sleep(for: .seconds(2))
            }
        }
        #else
        message = "Live screen sharing requires a physical iPhone."
        #endif
    }

    #if canImport(ScreenCaptureKit)
    func selected(_ filter: SCContentFilter, from observer: LiveCapture) async {
        guard capture === observer else { return }
        if stream != nil {
            stop("Screen sharing changed. Start Live Translation to use the new selection.")
            return
        }
        guard phase == .picker else { return }
        phase = .starting
        do {
            try prepareWindow()
            stage = "Screen capture"
            let config = SCStreamConfiguration()
            config.capturesAudio = false
            let size = filter.contentRect.size
            if size.width > 0 && size.height > 0 {
                let scale = min(CGFloat(filter.pointPixelScale), 1600 / max(size.width, size.height))
                config.width = max(2, Int(size.width * scale) / 2 * 2)
                config.height = max(2, Int(size.height * scale) / 2 * 2)
            }
            let sourceStream = SCStream(filter: filter, configuration: config, delegate: observer)
            self.stream = sourceStream
            try sourceStream.addStreamOutput(observer, type: .screen, sampleHandlerQueue: observer.queue)
            try await sourceStream.startCapture()
            guard capture === observer else {
                try? await sourceStream.stopCapture()
                return
            }
        } catch { if capture === observer { failed(error) } }
    }
    #endif

    private func prepareWindow() throws {
        stage = "Playback audio session"
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try audio.setActive(true)
        audioActive = true
        stage = "PiP controller"
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: display, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        pip = controller
        controller.delegate = self
        controller.requiresLinearPlayback = true
        waitForPreview()
        if movingScope { primeScopeWindow() }
    }

    private func waitForPreview() {
        phase = .starting
        startTimeout?.cancel()
        startTimeout = Task { [weak self] in
            let deadline = ContinuousClock.now.advanced(by: .seconds(12))
            while !Task.isCancelled, let self, phase == .starting {
                if windowReadiness.canOpen {
                    phase = .readyToOpen
                    return
                }
                if ContinuousClock.now >= deadline {
                    stop("The preview did not become ready for PiP. " + diagnostics())
                    return
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private var previewView: UIView? { display.superlayer?.delegate as? UIView }

    private var windowReadiness: FloatingWindowReadiness {
        let view = previewView
        let window = view?.window
        let visible = view.flatMap { view in window.map { $0.bounds.intersects(view.convert(view.bounds, to: $0)) } } ?? false
        return FloatingWindowReadiness(frameEnqueued: framesPresented > 0, frameDisplayable: display.isReadyForDisplay,
                                       previewVisible: visible, foregroundActive: window?.windowScene?.activationState == .foregroundActive,
                                       pipPossible: pip?.isPictureInPicturePossible == true)
    }

    private func diagnostics() -> String {
        let state = windowReadiness
        return "Stage: \(stage). Preview attached: \(previewView?.window != nil). On screen: \(state.previewVisible). " +
            "Frames enqueued: \(framesPresented). First frame displayable: \(state.frameDisplayable). " +
            "Scene active: \(state.foregroundActive). PiP possible: \(state.pipPossible)."
    }

    private func failed(_ error: any Error) {
        let e = error as NSError
        let underlying = e.userInfo[NSUnderlyingErrorKey] as? NSError
        let cause = underlying.map { " Underlying: \($0.domain) \($0.code)." } ?? ""
        let atStart = startSnapshot.map { " At start: " + $0 } ?? ""
        stop("\(e.localizedDescription) [\(e.domain) \(e.code)]." + cause + " " + diagnostics() + atStart)
    }

    /// Called synchronously by the floating-window button after the sharing picker has dismissed.
    func openFloatingWindow() {
        guard phase == .readyToOpen, let pip else { return }
        guard windowReadiness.canOpen else { waitForPreview(); return }
        phase = .opening
        stage = "Opening PiP from button"
        startSnapshot = diagnostics()
        startTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, phase == .opening else { return }
            stop("The floating window did not open. " + diagnostics())
        }
        pip.startPictureInPicture()
    }

    #if canImport(ScreenCaptureKit)
    func received(_ frame: LiveSample, from observer: LiveCapture) {
        guard capture === observer, let sessionID else { return }
        guard !movingScope || phase == .live else { return }
        receive(frame, session: sessionID)
    }
    #endif

    // PiP needs one video frame before it opens. Subsequent tracking misses
    // leave the displayed buffer in place, including its detectable border.
    private func primeScopeWindow() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 480, height: 300)
        let card = UIGraphicsImageRenderer(size: size, format: format).image { canvas in
            UIColor(white: 0.10, alpha: 1).setFill()
            canvas.fill(CGRect(origin: .zero, size: size))
        }
        if let image = card.cgImage { _ = present(image, [], [:]) }
    }

    private func receive(_ sample: LiveSample, session: UUID) {
        guard sessionID == session, [.starting, .readyToOpen, .opening, .live].contains(phase) else { return }
        guard case let .content(frame) = sample else {
            if !trackingInterrupted {
                processing?.cancel()
                processing = nil
                pendingNearbyFrame = nil
                sequence.invalidate()
                trackingInterrupted = true
            }
            return
        }
        let moved = frame.area != area || frame.screenSize != lastScreen || frame.orientation != lastOrientation
        if moved {
            pendingNearbyFrame = nil
            sequence.invalidate()
        } else if movingScope && processing != nil {
            // Scrolling and animation can change every capture. Finish a coherent
            // translation, then process just the freshest waiting frame.
            pendingNearbyFrame = frame
            return
        }
        area = frame.area
        lastScreen = frame.screenSize
        lastOrientation = frame.orientation
        trackingInterrupted = false
        let image = frame.image
        guard sequence.admit(signature: frame.signature, width: image.width, height: image.height) else { return }
        processing?.cancel()
        // A new target gets an immediate preview. Refresh a stationary target
        // in one paint so its readable labels survive capture noise and reacquisition.
        let progressive = !movingScope || moved
        if progressive { guard present(image, [], [:]) else { return } }
        let ticket = sequence.generation
        processing = Task {
            defer { finishFrame(ticket, session: session) }
            do {
                try await Task.sleep(for: .milliseconds(250))
                let regions = try await VisionRecognition.regions(in: image)
                try Task.checkCancellation()
                guard sessionID == session, sequence.accepts(ticket) else { return }
                try await translate(image, regions, ticket: ticket, session: session, progressive: progressive)
            } catch is CancellationError {
            } catch {
                if sessionID == session, sequence.accepts(ticket), !Task.isCancelled { failed(error) }
            }
        }
    }

    private func finishFrame(_ ticket: Int, session: UUID) {
        guard sessionID == session, sequence.accepts(ticket) else { return }
        processing = nil
        if let frame = pendingNearbyFrame {
            pendingNearbyFrame = nil
            receive(.content(frame), session: session)
        }
    }

    private func translate(_ image: CGImage, _ regions: [TextRegion], ticket: Int, session: UUID, progressive: Bool) async throws {
        var results: [String: RegionTranslation] = [:]
        let groups = Dictionary(grouping: regions, by: \.rawText)
        var missing: [TextRegion] = []
        for region in regions where groups[region.rawText]?.first?.id == region.id {
            if let result = cache[region.rawText] {
                for match in groups[region.rawText] ?? [] { results[match.id] = result }
            } else { missing.append(region) }
        }
        guard !missing.isEmpty else {
            _ = present(image, regions, results)
            return
        }
        if progressive && !results.isEmpty { guard present(image, regions, results) else { return } }
        var lastPaint = -Double.infinity
        let sources = Dictionary(uniqueKeysWithValues: missing.map { ($0.id, $0.rawText) })
        try await AppleTranslationEngine.translate(missing, preference: preference) { id, result in
            try Task.checkCancellation()
            guard self.sessionID == session, self.sequence.accepts(ticket), let text = sources[id] else { throw CancellationError() }
            if self.cache.count >= 512 { self.cache.removeAll(keepingCapacity: true) }
            self.cache[text] = result
            for match in groups[text] ?? [] { results[match.id] = result }
            let now = ProcessInfo.processInfo.systemUptime
            if progressive && now - lastPaint >= 0.2 {
                guard self.present(image, regions, results) else { throw CancellationError() }
                lastPaint = now
            }
        }
        guard sessionID == session, sequence.accepts(ticket), !Task.isCancelled else { return }
        _ = present(image, regions, results)
    }

    private func present(_ image: CGImage, _ regions: [TextRegion], _ results: [String: RegionTranslation]) -> Bool {
        guard let sample = LiveVideo.sample(image: image, regions: regions, results: results, nearby: movingScope, edge: area?.edge) else {
            stop("This frame could not be displayed. Start live translation again.")
            return false
        }
        let ready = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(sample)
        var outcome = receiver.enqueueImmediately(ready)
        if case .cancelledDueToFlushRequiredToResume = outcome {
            receiver.flush()
            outcome = receiver.enqueueImmediately(ready)
        }
        switch outcome {
        case .enqueued, .enqueuedWithDecodeFailures:
            framesPresented += 1
            return true
        case .cancelledDueToError(let error), .cancelledDueToFlushRequiredToResume(let error):
            failed(error)
        default: stop("The floating window stopped receiving frames. Start live translation again.")
        }
        return false
    }

    #if canImport(ScreenCaptureKit)
    func captureFailed(_ error: any Error, at stage: String, from observer: LiveCapture) {
        guard capture === observer else { return }
        self.stage = stage
        failed(error)
    }

    func ended(_ observer: LiveCapture, message: String? = nil) {
        guard capture === observer else { return }
        stop(message)
    }

    #endif

    func stop(_ detail: String? = nil) {
        guard phase != .idle, phase != .stopping else { return }
        phase = .stopping
        message = detail
        startTimeout?.cancel()
        processing?.cancel()
        processing = nil
        pendingNearbyFrame = nil
        sessionID = nil
        #if canImport(ScreenCaptureKit)
        if let capture { SCContentSharingPicker.shared.remove(capture) }
        SCContentSharingPicker.shared.isActive = false
        capture = nil
        let oldStream = stream
        stream = nil
        #elseif DEBUG && targetEnvironment(simulator)
        fixtureTask?.cancel()
        fixtureTask = nil
        #endif
        pip?.delegate = nil
        pip?.stopPictureInPicture()
        pip = nil
        sequence = LiveFrameSequence()
        cache.removeAll()
        Task {
            await receiver.flush(removingDisplayedImage: true)
            #if canImport(ScreenCaptureKit)
            if let oldStream { try? await oldStream.stopCapture() }
            #endif
            if audioActive {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                audioActive = false
            }
            phase = .idle
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        guard controller === pip else { return }
        phase = .live
        startTimeout?.cancel()
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        if controller === pip { stop() }
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error) {
        if controller === pip { stage = "PiP start callback"; failed(error) }
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        if !playing, controller === pip, phase == .live { stop() }
    }
    func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool { false }
    func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize size: CMVideoDimensions) {}
    func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval interval: CMTime,
                                    completion completionHandler: @escaping @Sendable () -> Void) { completionHandler() }
}

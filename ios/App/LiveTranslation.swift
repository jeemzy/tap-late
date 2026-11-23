import AVKit
import Observation
import Translation
import TapLateCore

enum LiveTranslationPhase { case idle, checking, picker, starting, live, stopping }

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
    @ObservationIgnored private var sessionID: UUID?
    #if canImport(ScreenCaptureKit)
    @ObservationIgnored private var capture: LiveCapture?
    @ObservationIgnored private var stream: SCStream?
    #elseif DEBUG && targetEnvironment(simulator)
    @ObservationIgnored private var fixtureTask: Task<Void, Never>?
    private(set) var sampleDescription = ""
    #endif
    @ObservationIgnored private var pip: AVPictureInPictureController?
    @ObservationIgnored private var possible: NSKeyValueObservation?
    @ObservationIgnored private var startTimeout: Task<Void, Never>?
    @ObservationIgnored private var processing: Task<Void, Never>?
    @ObservationIgnored private var sequence = LiveFrameSequence()
    @ObservationIgnored private var cache: [String: RegionTranslation] = [:]
    @ObservationIgnored private var preference = ApplePreference.fast
    @ObservationIgnored private var audioActive = false
    @ObservationIgnored private var startingPiP = false

    override init() {
        super.init()
        display.preventsCapture = true
        display.videoGravity = .resizeAspect
        synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        synchronizer.setRate(1, time: now, atHostTime: now)
    }

    func start(scope: LiveReadingScope, zone: ReadingZone, engine: ApplePreference) async {
        guard phase == .idle else { return }
        message = nil
        framesPresented = 0
        stage = "PiP availability"
        let supported = AVPictureInPictureController.isPictureInPictureSupported()
        #if canImport(ScreenCaptureKit)
        guard supported else {
            message = "Picture in Picture is unavailable on this device."
            return
        }
        sessionID = UUID()
        let observer = LiveCapture(owner: self, scope: scope, zone: zone)
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
        phase = .starting
        if supported {
            do { try prepareWindow() }
            catch { failed(error); return }
        } else {
            message = "PiP unavailable on this simulator. Showing the sample frames inline."
        }
        let sampler = LiveFrameSampler(scope: scope, zone: zone)
        fixtureTask = Task {
            var page = 0
            while !Task.isCancelled, sessionID == id {
                guard let sample = LiveSamplePages.sample(page),
                      let frame = sample.withUnsafeSampleBuffer({ sampler.frame($0, orientation: .up) }) else {
                    stop("Could not prepare the simulator sample page.")
                    return
                }
                receive(frame.0, signature: frame.1, session: id)
                if sessionID == id {
                    sampleDescription = "\(page == 0 ? "Camera" : "Tripod") · \(frame.0.width) × \(frame.0.height)"
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
        possible = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.startWindowIfReady() }
        }
        startTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, phase == .starting else { return }
            stop("Timed out waiting for PiP. " + diagnostics())
        }
    }

    private func diagnostics() -> String {
        let view = display.superlayer?.delegate as? UIView
        let attached = view?.window != nil
        let visible = view.flatMap { view in view.window.map { $0.bounds.intersects(view.convert(view.bounds, to: $0)) } } ?? false
        return "Stage: \(stage). Preview attached: \(attached). On screen: \(visible). Frames enqueued: \(framesPresented). PiP possible: \(pip?.isPictureInPicturePossible == true)."
    }

    private func failed(_ error: any Error) {
        let e = error as NSError
        let underlying = e.userInfo[NSUnderlyingErrorKey] as? NSError
        let cause = underlying.map { " Underlying: \($0.domain) \($0.code)." } ?? ""
        stop("\(e.localizedDescription) [\(e.domain) \(e.code)]." + cause + " " + diagnostics())
    }

    private func startWindowIfReady() {
        guard phase == .starting, !startingPiP, sequence.generation > 0,
              let pip, pip.isPictureInPicturePossible else { return }
        stage = "Opening PiP"
        startingPiP = true
        pip.startPictureInPicture()
    }

    #if canImport(ScreenCaptureKit)
    func received(_ image: CGImage, signature: [UInt8], from observer: LiveCapture) {
        guard capture === observer, let sessionID else { return }
        receive(image, signature: signature, session: sessionID)
    }
    #endif

    private func receive(_ image: CGImage, signature: [UInt8], session: UUID) {
        guard sessionID == session, phase == .starting || phase == .live,
              sequence.admit(signature: signature, width: image.width, height: image.height) else { return }
        processing?.cancel()
        guard present(image, [], [:]) else { return }
        startWindowIfReady()
        let ticket = sequence.generation
        processing = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                let regions = try await VisionRecognition.regions(in: image)
                try Task.checkCancellation()
                guard sessionID == session, sequence.accepts(ticket) else { return }
                try await translate(image, regions, ticket: ticket, session: session)
            } catch is CancellationError {
            } catch {
                if sessionID == session, sequence.accepts(ticket), !Task.isCancelled { failed(error) }
            }
        }
    }

    private func translate(_ image: CGImage, _ regions: [TextRegion], ticket: Int, session: UUID) async throws {
        var results: [String: RegionTranslation] = [:]
        let groups = Dictionary(grouping: regions, by: \.rawText)
        var missing: [TextRegion] = []
        for region in regions where groups[region.rawText]?.first?.id == region.id {
            if let result = cache[region.rawText] {
                for match in groups[region.rawText] ?? [] { results[match.id] = result }
            } else { missing.append(region) }
        }
        if !results.isEmpty { guard present(image, regions, results) else { return } }
        guard !missing.isEmpty else { return }
        var lastPaint = -Double.infinity
        let sources = Dictionary(uniqueKeysWithValues: missing.map { ($0.id, $0.rawText) })
        try await AppleTranslationEngine.translate(missing, preference: preference) { id, result in
            try Task.checkCancellation()
            guard self.sessionID == session, self.sequence.accepts(ticket), let text = sources[id] else { throw CancellationError() }
            if self.cache.count >= 512 { self.cache.removeAll(keepingCapacity: true) }
            self.cache[text] = result
            for match in groups[text] ?? [] { results[match.id] = result }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastPaint >= 0.2 {
                guard self.present(image, regions, results) else { throw CancellationError() }
                lastPaint = now
            }
        }
        guard sessionID == session, sequence.accepts(ticket), !Task.isCancelled else { return }
        _ = present(image, regions, results)
    }

    private func present(_ image: CGImage, _ regions: [TextRegion], _ results: [String: RegionTranslation]) -> Bool {
        guard let sample = LiveVideo.sample(image: image, regions: regions, results: results) else {
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
        possible = nil
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
        startingPiP = false
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

import AVKit
import Observation
import Translation
import TapLateCore

enum LiveTranslationPhase { case idle, checking, picker, starting, live, stopping }

#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit

@MainActor @Observable final class LiveTranslation: NSObject, AVPictureInPictureControllerDelegate,
    AVPictureInPictureSampleBufferPlaybackDelegate {
    private(set) var phase: LiveTranslationPhase = .idle
    private(set) var message: String?
    let display = AVSampleBufferDisplayLayer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    @ObservationIgnored private lazy var receiver = synchronizer.sampleBufferReceiver(adding: display.sampleBufferRenderer)

    @ObservationIgnored private var capture: LiveCapture?
    @ObservationIgnored private var stream: SCStream?
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
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            message = "Picture in Picture is unavailable on this device."
            return
        }
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
        picker.present()
    }

    func selected(_ filter: SCContentFilter, from observer: LiveCapture) async {
        guard capture === observer else { return }
        if stream != nil {
            stop("Screen sharing changed. Start Live Translation to use the new selection.")
            return
        }
        guard phase == .picker else { return }
        phase = .starting
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try audio.setActive(true)
            audioActive = true
            let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: display, playbackDelegate: self)
            let controller = AVPictureInPictureController(contentSource: source)
            pip = controller
            controller.delegate = self
            controller.requiresLinearPlayback = true
            possible = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.startWindowIfReady() }
            }
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
            startTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled, let self, self.capture === observer, self.phase == .starting else { return }
                self.stop("The floating window couldn’t start. Check Picture in Picture in iPhone Settings and try again.")
            }
        } catch { ended(observer, message: error.localizedDescription) }
    }

    private func startWindowIfReady() {
        guard phase == .starting, !startingPiP, sequence.generation > 0,
              let pip, pip.isPictureInPicturePossible else { return }
        startingPiP = true
        pip.startPictureInPicture()
    }

    func received(_ image: CGImage, signature: [UInt8], from observer: LiveCapture) {
        guard capture === observer, phase == .starting || phase == .live,
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
                guard capture === observer, sequence.accepts(ticket) else { return }
                try await translate(image, regions, ticket: ticket, observer: observer)
            } catch is CancellationError {
            } catch {
                if capture === observer, sequence.accepts(ticket), !Task.isCancelled { stop(error.localizedDescription) }
            }
        }
    }

    private func translate(_ image: CGImage, _ regions: [TextRegion], ticket: Int, observer: LiveCapture) async throws {
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
            guard self.capture === observer, self.sequence.accepts(ticket), let text = sources[id] else { throw CancellationError() }
            if self.cache.count >= 512 { self.cache.removeAll(keepingCapacity: true) }
            self.cache[text] = result
            for match in groups[text] ?? [] { results[match.id] = result }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastPaint >= 0.2 {
                guard self.present(image, regions, results) else { throw CancellationError() }
                lastPaint = now
            }
        }
        guard capture === observer, sequence.accepts(ticket), !Task.isCancelled else { return }
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
        case .enqueued, .enqueuedWithDecodeFailures: return true
        case .cancelledDueToError(let error), .cancelledDueToFlushRequiredToResume(let error):
            stop(error.localizedDescription)
        default: stop("The floating window stopped receiving frames. Start live translation again.")
        }
        return false
    }

    func ended(_ observer: LiveCapture, message: String? = nil) {
        guard capture === observer else { return }
        stop(message)
    }

    func stop(_ detail: String? = nil) {
        guard phase != .idle, phase != .stopping else { return }
        phase = .stopping
        message = detail
        startTimeout?.cancel()
        processing?.cancel()
        processing = nil
        possible = nil
        if let capture { SCContentSharingPicker.shared.remove(capture) }
        SCContentSharingPicker.shared.isActive = false
        capture = nil
        let oldStream = stream
        stream = nil
        pip?.delegate = nil
        pip?.stopPictureInPicture()
        pip = nil
        startingPiP = false
        sequence = LiveFrameSequence()
        cache.removeAll()
        Task {
            await receiver.flush(removingDisplayedImage: true)
            if let oldStream { try? await oldStream.stopCapture() }
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
        if controller === pip { stop(error.localizedDescription) }
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
#else
// The iPhone simulator SDK does not ship ScreenCaptureKit.
@MainActor @Observable final class LiveTranslation {
    let phase = LiveTranslationPhase.idle
    let display = AVSampleBufferDisplayLayer()
    private(set) var message: String?

    func start(scope: LiveReadingScope, zone: ReadingZone, engine: ApplePreference) async {
        message = "Live screen sharing requires a physical iPhone."
    }

    func stop() { message = nil }
}
#endif

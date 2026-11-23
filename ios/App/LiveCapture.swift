@preconcurrency import ScreenCaptureKit
import CoreImage
import TapLateCore

/// Each picker and stream has its own observer, so delayed callbacks from a previous run cannot restart capture.
final class LiveCapture: NSObject, SCContentSharingPickerObserver, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    private weak var owner: LiveTranslation?
    let queue = DispatchQueue(label: "com.jeemzy.taplate.live.frames", qos: .userInitiated)
    private let sampler: LiveFrameSampler
    // Accessed only on the stream's sample-handler queue. Keep just the last sample, including the final settled frame.
    private var pending: CMSampleBuffer?
    private var scheduled = false

    init(owner: LiveTranslation, scope: LiveReadingScope, zone: ReadingZone) {
        self.owner = owner
        self.sampler = LiveFrameSampler(scope: scope, zone: zone)
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in await owner?.selected(filter, from: self) }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        if stream == nil { ended() }
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) { ended(error.localizedDescription) }
    func stream(_ stream: SCStream, didStopWithError error: any Error) { ended(error.localizedDescription) }
    func streamDidBecomeInactive(_ stream: SCStream) { ended() }

    private func ended(_ message: String? = nil) {
        Task { @MainActor in owner?.ended(self, message: message) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid else { return }
        let metadata = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                        as? [[SCStreamFrameInfo: Any]])?.first
        if let raw = metadata?[.status] as? Int, let status = SCFrameStatus(rawValue: raw) {
            switch status {
            case .blank, .suspended, .stopped:
                pending = nil
                ended()
                return
            case .idle: return
            default: break
            }
        }
        guard buffer.imageBuffer != nil else { return }
        pending = buffer
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + .milliseconds(200)) { [weak self] in self?.deliver() }
    }

    private func deliver() {
        scheduled = false
        guard let buffer = pending else { return }
        pending = nil
        let metadata = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                        as? [[SCStreamFrameInfo: Any]])?.first
        let raw = metadata?[.videoOrientation] as? UInt32 ?? CGImagePropertyOrientation.up.rawValue
        let orientation = CGImagePropertyOrientation(rawValue: raw) ?? .up
        guard let (image, signature) = sampler.frame(buffer, orientation: orientation) else { return }
        Task { @MainActor in owner?.received(image, signature: signature, from: self) }
    }
}

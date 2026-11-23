import AVFoundation
import CoreImage
import UIKit
import TapLateCore

/// The stream output owns this object and calls it on its serial queue.
final class LiveFrameSampler {
    // The capture stream continues when JD owns the foreground. Avoid submitting background GPU work.
    private let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
    let scope: LiveReadingScope
    let zone: ReadingZone

    init(scope: LiveReadingScope, zone: ReadingZone) {
        self.scope = scope
        self.zone = zone
    }

    func frame(_ buffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) -> (CGImage, [UInt8])? {
        guard let pixels = buffer.imageBuffer else { return nil }
        let image = CIImage(cvPixelBuffer: pixels).oriented(orientation)
        let extent = image.extent.integral
        let crop = zone.crop(scope: scope, width: Int(extent.width), height: Int(extent.height))
        let bounds = CGRect(x: extent.minX, y: extent.maxY - crop.maxY, width: crop.width, height: crop.height)
        guard let snapshot = context.createCGImage(image, from: bounds) else { return nil }
        let width = 96, height = 96
        var signature = [UInt8](repeating: 0, count: width * height)
        let sampled = signature.withUnsafeMutableBytes { bytes -> Bool in
            guard let gray = CGContext(data: bytes.baseAddress, width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: width,
                                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            gray.interpolationQuality = .medium
            gray.draw(snapshot, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return sampled ? (snapshot, signature) : nil
    }
}

@MainActor enum LiveVideo {
    static func sample(image: CGImage, regions: [TextRegion], results: [String: RegionTranslation]) -> sending CMSampleBuffer? {
        var pixels: CVPixelBuffer?
        let width = image.width, height = image.height
        let options: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                  options as CFDictionary, &pixels) == kCVReturnSuccess, let pixels else { return nil }
        CVPixelBufferLockBaseAddress(pixels, [])
        let rendered = draw(image, regions, results, into: pixels)
        CVPixelBufferUnlockBaseAddress(pixels, [])
        guard rendered else { return nil }
        return timedSample(pixels)
    }

    // Each call creates a distinct, ready sample. The caller receives its sole Swift reference.
    nonisolated private static func timedSample(_ pixels: CVPixelBuffer) -> sending CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels,
                                                          formatDescriptionOut: &format) == noErr, let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels, formatDescription: format,
                                                       sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if let entries = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let entry = unsafeBitCast(CFArrayGetValueAtIndex(entries, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(entry, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    private static func draw(_ image: CGImage, _ regions: [TextRegion], _ results: [String: RegionTranslation],
                             into pixels: CVPixelBuffer) -> Bool {
        let flags = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: flags) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.translateBy(x: 0, y: CGFloat(image.height))
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }
        let label = OverlayTextLabel()
        for region in regions {
            guard let result = results[region.id], let translated = result.translation, translated != region.rawText else { continue }
            let rect = CGRect(x: region.rect.x, y: region.rect.y, width: region.rect.width, height: region.rect.height)
            let foreground = region.appearance?.foreground ?? TextInk(red: 0, green: 0, blue: 0)
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.setFillColor(region.appearance?.background.uiColor.cgColor ?? UIColor.white.cgColor)
            ctx.fill(rect)
            ctx.translateBy(x: rect.minX, y: rect.minY)
            label.bounds = CGRect(origin: .zero, size: rect.size)
            label.display(result, foreground: foreground)
            label.drawText(in: label.bounds)
            ctx.restoreGState()
        }
        return true
    }
}

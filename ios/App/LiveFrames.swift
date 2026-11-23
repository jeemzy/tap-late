import AVFoundation
import CoreImage
import UIKit
import TapLateCore

struct SampledLiveFrame {
    let image: CGImage
    let signature: [UInt8]
    let area: NearbyArea?
    let screenSize: CGSize
    let orientation: CGImagePropertyOrientation
}

enum LiveSample {
    case locating
    case content(SampledLiveFrame)
}

/// The stream output owns this object and calls it on its serial queue.
final class LiveFrameSampler {
    // The capture stream continues when JD owns the foreground. Avoid submitting background GPU work.
    private let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
    let scope: LiveReadingScope
    private var thumbnailWindow: CGRect?
    private var lastEdge: ReadingEdge?
    private var lastExtent: CGRect?
    private var lastOrientation: CGImagePropertyOrientation?

    init(scope: LiveReadingScope) { self.scope = scope }

    func frame(_ buffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) -> LiveSample? {
        guard let pixels = buffer.imageBuffer else { return nil }
        let image = CIImage(cvPixelBuffer: pixels).oriented(orientation)
        let extent = image.extent.integral
        if lastExtent != extent || lastOrientation != orientation { lastEdge = nil; thumbnailWindow = nil }
        lastExtent = extent
        lastOrientation = orientation
        var area: NearbyArea?
        var bounds = extent
        if scope == .near {
            guard let window = locate(in: image),
                  let nearby = NearbyArea(window: window, screen: extent.size, previous: lastEdge) else {
                return .locating
            }
            lastEdge = nearby.edge
            area = nearby
            bounds = CGRect(x: extent.minX + nearby.crop.minX, y: extent.maxY - nearby.crop.maxY,
                            width: nearby.crop.width, height: nearby.crop.height)
        }
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
        guard sampled else { return nil }
        return .content(SampledLiveFrame(image: snapshot, signature: signature, area: area,
                                         screenSize: extent.size, orientation: orientation))
    }

    private func locate(in image: CIImage) -> CGRect? {
        let size = image.extent.size
        let scale = min(1, 960 / max(size.width, size.height))
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let thumbnail = context.createCGImage(small, from: small.extent.integral) else { return nil }
        let w = thumbnail.width, h = thumbnail.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let rgb = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue |
                                        CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            rgb.draw(thumbnail, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard rendered, let window = ScopeBorderDetector(rgba: pixels, width: w, height: h).window(previous: thumbnailWindow) else { return nil }
        thumbnailWindow = window
        return window.applying(CGAffineTransform(scaleX: size.width / CGFloat(w), y: size.height / CGFloat(h)))
    }
}

@MainActor enum LiveVideo {
    static func sample(image: CGImage, regions: [TextRegion], results: [String: RegionTranslation], nearby: Bool = false, edge: ReadingEdge? = nil) -> CMReadySampleBuffer<CVReadOnlyPixelBuffer>? {
        let attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(width: nearby ? 480 : image.width, height: nearby ? 300 : image.height),
            compatibility: [.cgBitmapContext, .ioSurfaceCoreAnimation])
        guard let writable = try? CVMutablePixelBuffer(attributes) else { return nil }
        let rendered = writable.withUnsafeBuffer { pixels in
            guard CVPixelBufferLockBaseAddress(pixels, []) == kCVReturnSuccess else { return false }
            defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
            return draw(image, regions, results, nearby: nearby, edge: edge, into: pixels)
        }
        guard rendered else { return nil }
        let frame = CVReadOnlyPixelBuffer(writable)
        return CMReadySampleBuffer(pixelBuffer: frame, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()))
    }

    private static func draw(_ image: CGImage, _ regions: [TextRegion], _ results: [String: RegionTranslation],
                             nearby: Bool, edge: ReadingEdge?, into pixels: CVPixelBuffer) -> Bool {
        let flags = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels),
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: flags) else { return false }
        let canvas = CGSize(width: ctx.width, height: ctx.height)
        let inset = nearby ? (canvas.width * ScopeBorder.inset).rounded() : 0
        let content = CGRect(origin: .zero, size: canvas).insetBy(dx: inset, dy: inset)
        let scale = min(content.width / CGFloat(image.width), content.height / CGFloat(image.height))
        if nearby {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: canvas.height)
            ctx.scaleBy(x: 1, y: -1)
            ScopeBorder.draw(in: ctx, size: canvas, edge: edge)
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.translateBy(x: content.midX - CGFloat(image.width) * scale / 2,
                        y: content.midY - CGFloat(image.height) * scale / 2)
        ctx.scaleBy(x: scale, y: scale)
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
        ctx.restoreGState()
        return true
    }
}

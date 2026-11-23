import CoreImage
import Testing
import UIKit
import TapLateCore
@testable import TapLate

@MainActor struct LiveVideoTests {
    @Test func floatingWindowRequiresDisplayableVideoInAnActiveVisibleScene() {
        func readiness(enqueued: Bool = true, displayable: Bool = true, visible: Bool = true,
                       active: Bool = true, possible: Bool = true) -> FloatingWindowReadiness {
            FloatingWindowReadiness(frameEnqueued: enqueued, frameDisplayable: displayable, previewVisible: visible,
                                    foregroundActive: active, pipPossible: possible)
        }
        #expect(!readiness(displayable: false).canOpen)
        #expect(!readiness(active: false).canOpen)
        #expect(!readiness(enqueued: false).canOpen)
        #expect(!readiness(visible: false).canOpen)
        #expect(!readiness(possible: false).canOpen)
        #expect(readiness().canOpen)
    }

    @Test func wholeScreenKeepsBothDuplicateLabels() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 180, height: 300)
        let image = try #require(UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 200, width: 180, height: 100))
        }.cgImage)
        let sampler = LiveFrameSampler(scope: .whole)
        let appearance = TextAppearance(background: .init(red: 255, green: 255, blue: 255),
                                        foreground: .init(red: 0, green: 0, blue: 0))
        let regions = [12, 58].enumerated().map { index, y in
            TextRegion(id: String(index), rawText: "搜索", confidence: 1,
                       rect: .init(x: 12, y: Double(y), width: 120, height: 30), appearance: appearance)
        }
        let result = RegionTranslation(source: "搜索", translation: "Search")
        let translated = try #require(LiveVideo.sample(image: image, regions: regions, results: ["0": result, "1": result]))
        let frame = try #require(translated.withUnsafeSampleBuffer { sampler.frame($0, orientation: .up) })
        let labels = frame.signature
        // Both labels have white backgrounds. The space between them still belongs to the original page.
        for y in [16, 62] { #expect(labels[y * 96 / 300 * 96 + 12] > 240) }
        #expect(labels[48 * 96 / 300 * 96 + 12] < 5)
    }

    @Test func nearbyWindowHasAnOuterGreenRimAndInnerBlackRimWithClearContent() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 480, height: 300)
        let image = try #require(UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }.cgImage)
        let video = try #require(LiveVideo.sample(image: image, regions: [], results: [:], nearby: true, edge: .above))
        try video.withUnsafeSampleBuffer { sample in
            let pixels = try #require(sample.imageBuffer)
            CVPixelBufferLockBaseAddress(pixels, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
            let base = try #require(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
            func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
                let p = base + y * CVPixelBufferGetBytesPerRow(pixels) + 4*x
                return (Int(p[2]), Int(p[1]), Int(p[0]))
            }
            for (x, y) in [(2,150),(477,150),(240,2),(240,297)] {
                let (r,g,b) = rgb(x,y)
                #expect(g > r + 65 && g > b + 30)
            }
            for (x, y) in [(5,150),(474,150),(240,5),(240,294)] {
                let (r,g,b) = rgb(x,y)
                #expect(max(r,g,b) < 25)
            }
            let clearAcrossWidth = (12..<468).allSatisfy { x in
                let (r,g,b) = rgb(x,150)
                return min(r,g,b) > 248
            }
            #expect(clearAcrossWidth)
        }
    }

    @Test func trackingSurvivesACoveredEdgeButRejectsAnUnframedGreenCard() {
        let width = 320, height = 640
        let box = CGRect(x: 38, y: 123, width: 160, height: 100)
        func screen(coverTop: Bool = false, plain: Bool = false) -> ScopeBorderDetector {
            var pixels = [UInt8](repeating: 255, count: width * height * 4)
            for y in 123..<223 {
                for x in 38..<198 {
                    let depth = min(x - 38, 197 - x, y - 123, 222 - y)
                    let color: [UInt8]
                    if coverTop && depth < 4 && y < 128 { color = [190, 190, 190] }
                    else if depth < 2 || plain { color = [33, 156, 92] }
                    else if depth == 2 { color = [6, 6, 6] }
                    else { continue }
                    let i = (y * width + x) * 4
                    for c in 0..<3 { pixels[i+c] = color[c] }
                }
            }
            return ScopeBorderDetector(rgba: pixels, width: width, height: height)
        }
        #expect(screen().window(previous: nil) == box)
        #expect(screen(coverTop: true).window(previous: box) == box)
        #expect(screen(plain: true).window(previous: box) == nil)
    }

    @Test func scopeReadsOnlyAdjacentChineseAndRecoversAfterOcclusion() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 400, height: 800)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let sampler = LiveFrameSampler(scope: .near)
        let pageImage = try #require(renderer.image { _ in UIColor.black.setFill(); UIRectFill(CGRect(origin: .zero, size: size)) }.cgImage)
        let marked = try #require(LiveVideo.sample(image: pageImage, regions: [], results: [:], nearby: true))
        let ci = CIContext()
        let tile = try #require(marked.withUnsafeSampleBuffer { buffer -> CGImage? in
            guard let pixels = buffer.imageBuffer else { return nil }
            let image = CIImage(cvPixelBuffer: pixels)
            return ci.createCGImage(image, from: image.extent)
        })
        func sample(_ window: CGRect?, scrolled: Bool = false, rotated: Bool = false) throws -> SampledLiveFrame? {
            var page = try #require(renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let style: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 36), .foregroundColor: UIColor.black]
                ((scrolled ? "手机" : "相机") as NSString).draw(at: CGPoint(x: 44, y: 218), withAttributes: style)
                ("商品" as NSString).draw(at: CGPoint(x: 172, y: 490), withAttributes: style)
                if let window {
                    ctx.cgContext.saveGState()
                    UIBezierPath(roundedRect: window, cornerRadius: 15).addClip()
                    UIImage(cgImage: tile).draw(in: window)
                    ctx.cgContext.restoreGState()
                }
            }.cgImage)
            if rotated {
                let sideways = CIImage(cgImage: page).oriented(.left)
                page = try #require(ci.createCGImage(sideways, from: sideways.extent))
            }
            let input = try #require(LiveVideo.sample(image: page, regions: [], results: [:]))
            return input.withUnsafeSampleBuffer { sampler.frame($0, orientation: rotated ? .right : .up) }
        }
        for (box, scroll, rotate, edge, expected) in [
            (CGRect(x: 26, y: 70, width: 200, height: 125), false, false, ReadingEdge.below, "相机"),
            (CGRect(x: 26, y: 70, width: 200, height: 125), true, false, .below, "手机"),
            (CGRect(x: 118, y: 610, width: 240, height: 150), false, true, .above, "商品")
        ] {
            let sampled = try sample(box, scrolled: scroll, rotated: rotate)
            let frame = try #require(sampled)
            let area = try #require(frame.area)
            #expect(area.edge == edge)
            #expect(!area.crop.intersects(box))
            #expect(abs(area.crop.minX - box.minX) <= 3)
            #expect(abs(area.crop.width - box.width) <= 4)
            let words = try await VisionRecognition.regions(in: frame.image).map(\.rawText).joined().replacingOccurrences(of: " ", with: "")
            #expect(words == expected)
        }
        for hidden in [nil, CGRect(x: -150, y: 40, width: 200, height: 125)] as [CGRect?] {
            let missing = try sample(hidden)
            #expect(missing == nil)
        }
        let recovered = try sample(CGRect(x: 26, y: 70, width: 200, height: 125))
        #expect(recovered != nil)
    }
}

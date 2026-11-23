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
        let sample = try #require(translated.withUnsafeSampleBuffer { sampler.frame($0, orientation: .up) })
        guard case .content(let frame) = sample else { Issue.record("Missing whole-screen frame"); return }
        let labels = frame.signature
        // Both labels have white backgrounds. The space between them still belongs to the original page.
        for y in [16, 62] { #expect(labels[y * 96 / 300 * 96 + 12] > 240) }
        #expect(labels[48 * 96 / 300 * 96 + 12] < 5)
    }

    @Test func scopeReadsOnlyAdjacentChineseAndRecoversAfterLosingMarks() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 400, height: 800)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let sampler = LiveFrameSampler(scope: .near)
        let markerImage = try #require(renderer.image { _ in UIColor.black.setFill(); UIRectFill(CGRect(origin: .zero, size: size)) }.cgImage)
        let marked = try #require(LiveVideo.sample(image: markerImage, regions: [], results: [:], marked: true))
        let ci = CIContext()
        let tile = try #require(marked.withUnsafeSampleBuffer { buffer -> CGImage? in
            guard let pixels = buffer.imageBuffer else { return nil }
            let image = CIImage(cvPixelBuffer: pixels)
            return ci.createCGImage(image, from: image.extent)
        })
        func sample(_ window: CGRect?, scrolled: Bool = false, rotated: Bool = false) throws -> LiveSample {
            var page = try #require(renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let style: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 36), .foregroundColor: UIColor.black]
                ((scrolled ? "手机" : "相机") as NSString).draw(at: CGPoint(x: 44, y: 218), withAttributes: style)
                ("商品" as NSString).draw(at: CGPoint(x: 172, y: 490), withAttributes: style)
                if let window { UIImage(cgImage: tile).draw(in: window) }
            }.cgImage)
            if rotated {
                let sideways = CIImage(cgImage: page).oriented(.left)
                page = try #require(ci.createCGImage(sideways, from: sideways.extent))
            }
            let input = try #require(LiveVideo.sample(image: page, regions: [], results: [:]))
            return try #require(input.withUnsafeSampleBuffer { sampler.frame($0, orientation: rotated ? .right : .up) })
        }
        for (box, scroll, rotate, edge, expected) in [
            (CGRect(x: 26, y: 70, width: 200, height: 125), false, false, ReadingEdge.below, "相机"),
            (CGRect(x: 26, y: 70, width: 200, height: 125), true, false, .below, "手机"),
            (CGRect(x: 118, y: 610, width: 240, height: 150), false, true, .above, "商品")
        ] {
            guard case .content(let frame) = try sample(box, scrolled: scroll, rotated: rotate) else {
                Issue.record("Window was not located"); return
            }
            let area = try #require(frame.area)
            #expect(area.edge == edge)
            #expect(!area.crop.intersects(box))
            #expect(abs(area.crop.minX - box.minX) <= 3)
            #expect(abs(area.crop.width - box.width) <= 4)
            let words = try await VisionRecognition.regions(in: frame.image).map(\.rawText).joined().replacingOccurrences(of: " ", with: "")
            #expect(words == expected)
        }
        for hidden in [nil, CGRect(x: -150, y: 40, width: 200, height: 125)] as [CGRect?] {
            guard case .locating = try sample(hidden) else { Issue.record("Locked onto a hidden window"); return }
        }
        guard case .content = try sample(CGRect(x: 26, y: 70, width: 200, height: 125)) else {
            Issue.record("Could not reacquire window"); return
        }
    }
}

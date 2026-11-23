import CoreImage
import Testing
import UIKit
import TapLateCore
@testable import TapLate

@MainActor struct LiveVideoTests {
    @Test func cropFollowsUprightOrientationAndKeepsBothDuplicateLabels() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 180, height: 300)
        let image = try #require(UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 200, width: 180, height: 100))
        }.cgImage)
        let raw = try #require(LiveVideo.sample(image: image, regions: [], results: [:]))
        let top = LiveFrameSampler(scope: .zone, zone: .top)
        let (upright, black) = try #require(raw.withUnsafeSampleBuffer { top.frame($0, orientation: .up) })
        let (rotated, white) = try #require(raw.withUnsafeSampleBuffer { top.frame($0, orientation: .down) })
        #expect(upright.height == 100 && rotated.height == 100)
        #expect((black.max() ?? 255) < 5)
        #expect((white.min() ?? 0) > 250)

        let appearance = TextAppearance(background: .init(red: 255, green: 255, blue: 255),
                                        foreground: .init(red: 0, green: 0, blue: 0))
        let regions = [12, 58].enumerated().map { index, y in
            TextRegion(id: String(index), rawText: "搜索", confidence: 1,
                       rect: .init(x: 12, y: Double(y), width: 120, height: 30), appearance: appearance)
        }
        let result = RegionTranslation(source: "搜索", translation: "Search")
        let translated = try #require(LiveVideo.sample(image: image, regions: regions, results: ["0": result, "1": result]))
        let (_, labels) = try #require(translated.withUnsafeSampleBuffer { top.frame($0, orientation: .up) })
        // Both labels have white backgrounds. The space between them still belongs to the original page.
        for y in [16, 62] { #expect(labels[y * 96 / 100 * 96 + 12] > 240) }
        #expect(labels[48 * 96 / 100 * 96 + 12] < 5)
    }
}

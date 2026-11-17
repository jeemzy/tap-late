#if DEBUG
import UIKit
import TapLateCore

/// Deterministic layout fixture. Never compiled into the installable Release IPA.
@MainActor final class PreviewEngine: ScreenshotEngine {
    static let regions = [
        TextRegion(id: "r001", rawText: "蓝色 旗舰款", confidence: 0.98, rect: PixelRect(x: 24, y: 420, width: 300, height: 42)),
        TextRegion(id: "r002", rawText: "¥88.00", confidence: 0.99, rect: PixelRect(x: 24, y: 492, width: 220, height: 46)),
        TextRegion(id: "r003", rawText: "加入购物车", confidence: 0.98, rect: PixelRect(x: 24, y: 780, width: 370, height: 48)),
        TextRegion(id: "r004", rawText: "顶部标签", confidence: 0.98, rect: PixelRect(x: 24, y: 10, width: 200, height: 40)),
        TextRegion(id: "r005", rawText: "底部标签", confidence: 0.98, rect: PixelRect(x: 24, y: 855, width: 200, height: 40))
    ]

    private static var pixelScale: Double { ProcessInfo.processInfo.arguments.contains("--large-image") ? 3 : 1 }
    func recognize(_ session: ScreenshotSession) async throws -> [TextRegion] {
        Self.regions.map { region in
            let r = region.rect, scale = Self.pixelScale
            return TextRegion(id: region.id, rawText: region.rawText, confidence: region.confidence,
                              rect: PixelRect(x: r.x * scale, y: r.y * scale, width: r.width * scale, height: r.height * scale))
        }
    }
    func translate(_ regions: [TextRegion], configuration: EngineConfiguration,
                   emit: @MainActor (String, RegionTranslation) throws -> Void) async throws {
        let text = ["r001": "Blue · premium", "r002": "¥88.00", "r003": "Add to cart", "r004": "Top label", "r005": "Bottom label"]
        for region in regions { try emit(region.id, RegionTranslation(source: region.rawText, translation: text[region.id])) }
    }

    static func image() -> CapturedImage {
        let size = CGSize(width: 420, height: 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = Self.pixelScale
        let data = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.88, green: 0.93, blue: 0.97, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 24, y: 115, width: 372, height: 260), cornerRadius: 20).fill()
            ("Screenshot layout fixture" as NSString).draw(at: CGPoint(x: 24, y: 70), withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.darkGray])
            for region in regions {
                let r = region.rect
                (region.rawText as NSString).draw(in: CGRect(x: r.x, y: r.y, width: r.width, height: r.height),
                                                 withAttributes: [.font: UIFont.systemFont(ofSize: 26), .foregroundColor: UIColor.black])
            }
            ("UI fixture · not an accuracy benchmark" as NSString).draw(at: CGPoint(x: 24, y: 735), withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.darkGray])
        }
        return CapturedImage(data: data, width: Int(420 * Self.pixelScale), height: Int(900 * Self.pixelScale))
    }
}
#endif

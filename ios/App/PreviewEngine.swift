#if DEBUG
import UIKit
import AppIntents
import UniformTypeIdentifiers
import TapLateCore

/// Deterministic layout fixture. Never compiled into the installable Release IPA.
@MainActor final class PreviewEngine: ScreenshotEngine {
    static let regions = [
        TextRegion(id: "r001", rawText: "蓝色 旗舰款", confidence: 0.98, rect: PixelRect(x: 24, y: 420, width: 300, height: 42)),
        TextRegion(id: "r002", rawText: "¥88.00", confidence: 0.99, rect: PixelRect(x: 24, y: 492, width: 220, height: 46)),
        TextRegion(id: "r003", rawText: "加入购物车", confidence: 0.98, rect: PixelRect(x: 24, y: 780, width: 370, height: 48)),
        TextRegion(id: "r004", rawText: "顶部标签", confidence: 0.98, rect: PixelRect(x: 24, y: 10, width: 200, height: 40)),
        TextRegion(id: "r005", rawText: "底部标签", confidence: 0.98, rect: PixelRect(x: 24, y: 855, width: 200, height: 40)),
        TextRegion(id: "r006", rawText: "我同意《隐私政策》", confidence: 0.98, rect: PixelRect(x: 24, y: 600, width: 330, height: 24)),
        TextRegion(id: "r007", rawText: "推荐使用第三方一键登录", confidence: 0.98, rect: PixelRect(x: 24, y: 625, width: 330, height: 24))
    ]

    private static var pixelScale: Double { ProcessInfo.processInfo.arguments.contains("--large-image") ? 3 : 1 }
    func recognize(_ session: ScreenshotSession) async throws -> [TextRegion] {
        let second = ProcessInfo.processInfo.arguments.contains("--warm-capture") && session.attempt.order == 2
        return Self.regions.map { region in
            let r = region.rect, scale = Self.pixelScale
            let source = second && region.id == "r001" ? "红色" : region.rawText
            return TextRegion(id: region.id, rawText: source, confidence: region.confidence,
                              rect: PixelRect(x: r.x * scale, y: r.y * scale, width: r.width * scale, height: r.height * scale))
        }
    }
    func translate(_ regions: [TextRegion], configuration: EngineConfiguration,
                   emit: @MainActor (String, RegionTranslation) throws -> Void) async throws {
        let agreement = "I agree to the Privacy Policy"
        let range = (agreement as NSString).range(of: "Privacy Policy")
        let blue = TextInk(red: 32, green: 122, blue: 222)
        let gray = TextInk(red: 119, green: 119, blue: 119)
        let text = ["r001": "Blue · premium", "r002": "¥88.00", "r003": "Add to cart", "r004": "Top label", "r005": "Bottom label",
                    "r006": agreement, "r007": "We recommend using a third-party sign-in service to sign in with one tap."]
        for region in regions {
            let colors: [TextColorSpan]? = region.id == "r006"
                ? [.init(location: 0, length: range.location, ink: gray),
                   .init(location: range.location, length: range.length, ink: blue)] : nil
            let translation = region.rawText == "红色" ? "Red" : text[region.id]
            try emit(region.id, RegionTranslation(source: region.rawText, translation: translation, colors: colors))
        }
    }

    static func submitSecondCapture() async throws {
        var intent = TranslateScreenshotIntent()
        intent.image = IntentFile(data: image(second: true).data, filename: "second.png", type: .png)
        _ = try await intent.perform()
    }

    static func image(second: Bool = false) -> CapturedImage {
        let size = CGSize(width: 420, height: 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = Self.pixelScale
        let data = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            (second ? UIColor.red : UIColor(red: 0.88, green: 0.93, blue: 0.97, alpha: 1)).setFill()
            UIBezierPath(roundedRect: CGRect(x: 24, y: 115, width: 372, height: 260), cornerRadius: 20).fill()
            ("Screenshot layout fixture" as NSString).draw(at: CGPoint(x: 24, y: 70), withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.darkGray])
            for region in regions {
                let r = region.rect
                let isCompact = region.id == "r006" || region.id == "r007"
                let source = second && region.id == "r001" ? "红色" : region.rawText
                let styled = NSMutableAttributedString(string: source,
                    attributes: [.font: UIFont.systemFont(ofSize: isCompact ? 17 : 26),
                                 .foregroundColor: isCompact ? UIColor(white: 0.47, alpha: 1) : UIColor.black])
                if region.id == "r006" {
                    let range = (region.rawText as NSString).range(of: "《隐私政策》")
                    styled.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
                }
                styled.draw(in: CGRect(x: r.x, y: r.y, width: r.width, height: r.height))
            }
            ("UI fixture · not an accuracy benchmark" as NSString).draw(at: CGPoint(x: 24, y: 735), withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.darkGray])
        }
        return CapturedImage(data: data, width: Int(420 * Self.pixelScale), height: Int(900 * Self.pixelScale))
    }
}
#endif

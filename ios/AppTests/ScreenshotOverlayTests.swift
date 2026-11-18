import Foundation
import Testing
import UIKit
import TapLateCore
@testable import TapLate

@Suite @MainActor struct ScreenshotOverlayTests {
    @Test func `samples separate gray and blue ink within the same source line`() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 100), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 100))
            let font = UIFont.systemFont(ofSize: 23, weight: .medium)
            ("已同意" as NSString).draw(at: CGPoint(x: 12, y: 17),
                                    withAttributes: [.font: font, .foregroundColor: UIColor(white: 0.61, alpha: 1)])
            ("服务协议" as NSString).draw(at: CGPoint(x: 93, y: 17),
                                     withAttributes: [.font: font, .foregroundColor: UIColor(red: 0.1, green: 0.48, blue: 0.90, alpha: 1)])
        }
        let source = try #require(image.cgImage)
        let line = CGRect(x: 12, y: 17, width: 175, height: 28)
        let base = try #require(ScreenshotInk.sample(source, in: line))
        let gray = try #require(ScreenshotInk.sample(source, in: CGRect(x: 12, y: 17, width: 70, height: 28),
                                                    background: base.background))
        let blue = try #require(ScreenshotInk.sample(source, in: CGRect(x: 93, y: 17, width: 94, height: 28),
                                                    background: base.background))
        #expect(base.background.red >= 245 && base.background.green >= 245 && base.background.blue >= 245)
        #expect(gray.foreground.red > 130 && gray.foreground.red < 190)
        #expect(gray.foreground.red == gray.foreground.blue)
        #expect(Int(blue.foreground.blue) > Int(blue.foreground.red) + 100)
        #expect(base.hasMixedInk)
    }

    @Test func `long translated rows stay inside their boxes and keep the complete result`() throws {
        let translation = "I have read and agree to the Privacy and Service Agreement"
        let label = OverlayTextLabel()
        label.frame = CGRect(x: 0, y: 0, width: 100, height: 20)
        let gray = TextInk(red: 152, green: 152, blue: 152)
        let blue = TextInk(red: 36, green: 121, blue: 225)
        let range = (translation as NSString).range(of: "Privacy and Service Agreement")
        let sourceStyle = TextAppearance(background: .init(red: 255, green: 255, blue: 255), foreground: gray,
                                         colors: [.init(location: range.location, length: range.length, ink: blue)])
        let formatted = FormattedTranslation.source(translation, appearance: sourceStyle)
        let colors = FormattedTranslation.colors(in: formatted, matching: translation)
        let result = RegionTranslation(source: "我已阅读并同意《隐私及服务协议》", translation: translation, colors: colors)
        let persisted = try JSONDecoder().decode(RegionTranslation.self, from: JSONEncoder().encode(result))
        label.display(persisted, foreground: gray)
        #expect(label.numberOfLines == 1)
        #expect(label.clipsToBounds)
        #expect(label.lineBreakMode == .byTruncatingTail)
        #expect(label.attributedText?.string == translation)
        #expect(result.translation == translation)
        let text = try #require(label.attributedText)
        let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        #expect(font.lineHeight <= label.bounds.height)
        #expect(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == gray.uiColor)
        #expect(text.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor == blue.uiColor)
    }

    @Test func `colliding source rectangles are excluded while tightly spaced rows stay eligible`() {
        let frames = [
            "first": CGRect(x: 10, y: 20, width: 100, height: 21),
            "second": CGRect(x: 10, y: 40, width: 200, height: 21),
            "third": CGRect(x: 10, y: 61, width: 200, height: 21),
            "side": CGRect(x: 211, y: 40, width: 80, height: 21)
        ]
        #expect(ScreenshotCanvas.overlappingIDs(in: frames) == ["first", "second"])
    }
}

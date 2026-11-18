import UIKit
import TapLateCore

final class OverlayTextLabel: UILabel {
    func display(_ result: RegionTranslation, foreground: TextInk) {
        guard let translation = result.translation else { attributedText = nil; return }
        let singleLine = translation.replacingOccurrences(of: "[\\r\\n\\u0085\\u2028\\u2029]", with: " ", options: .regularExpression)
        clipsToBounds = true
        numberOfLines = 1
        lineBreakMode = .byTruncatingTail
        textAlignment = .center
        isAccessibilityElement = false
        let reference = UIFont.systemFont(ofSize: 20, weight: .medium)
        let preferredSize = 20 * bounds.height / reference.lineHeight * 0.93
        let preferred = UIFont.systemFont(ofSize: preferredSize, weight: .medium)
        let fullWidth = (singleLine as NSString).size(withAttributes: [.font: preferred]).width
        let scale = min(1, max(0.74, (bounds.width - 1) / max(1, fullWidth)))
        let fitted = UIFont.systemFont(ofSize: preferredSize * scale, weight: .medium)
        let text = NSMutableAttributedString(string: singleLine,
                                             attributes: [.font: fitted, .foregroundColor: foreground.uiColor])
        for span in result.colors ?? [] {
            guard span.location >= 0, span.length > 0, span.location <= text.length,
                  span.length <= text.length - span.location else { continue }
            text.addAttribute(.foregroundColor, value: span.ink.uiColor,
                              range: NSRange(location: span.location, length: span.length))
        }
        attributedText = text
    }
}

extension TextInk {
    var uiColor: UIColor {
        UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    init?(color: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), alpha > 0.8 else { return nil }
        func channel(_ value: CGFloat) -> UInt8 { UInt8((min(1, max(0, value)) * 255).rounded()) }
        self.init(red: channel(red), green: channel(green), blue: channel(blue))
    }
}

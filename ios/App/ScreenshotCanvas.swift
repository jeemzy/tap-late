import SwiftUI
import TapLateCore

struct ScreenshotCanvas: UIViewRepresentable {
    let image: UIImage
    let regions: [TextRegion]
    let results: [String: RegionTranslation]
    let translated: Bool
    let selectedID: String?
    let coveredHeight: CGFloat
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CanvasScrollView {
        let scroll = CanvasScrollView()
        scroll.delegate = context.coordinator
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.accessibilityIdentifier = "screenshot-canvas"
        scroll.alwaysBounceVertical = true
        context.coordinator.scroll = scroll
        let canvas = UIView(frame: CGRect(origin: .zero, size: image.size))
        let original = UIImageView(image: image)
        original.frame = canvas.bounds
        canvas.addSubview(original)
        scroll.addSubview(canvas)
        scroll.contentSize = image.size
        context.coordinator.canvas = canvas
        scroll.onLayout = { [weak coordinator = context.coordinator] in coordinator?.fitIfNeeded() }
        return scroll
    }

    func updateUIView(_ scroll: CanvasScrollView, context: Context) {
        let c = context.coordinator
        c.onSelect = onSelect
        c.coveredHeight = coveredHeight
        let ids = Set(regions.map(\.id))
        for id in Array(c.buttons.keys) where !ids.contains(id) { c.buttons.removeValue(forKey: id)?.removeFromSuperview() }
        for region in regions {
            let button: UIButton
            if let existing = c.buttons[region.id] { button = existing }
            else {
                button = UIButton(type: .custom)
                button.accessibilityIdentifier = "region-" + region.id
                button.addAction(UIAction { [weak c] _ in c?.onSelect?(region.id) }, for: .touchUpInside)
                button.titleLabel?.numberOfLines = 0
                button.titleLabel?.lineBreakMode = .byTruncatingTail
                button.contentHorizontalAlignment = .center
                c.canvas?.addSubview(button)
                c.buttons[region.id] = button
            }
            let r = region.rect
            button.frame = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
            let text = results[region.id]?.translation
            button.setTitle(translated ? text : nil, for: .normal)
            let backing = image.backingColor(around: button.frame)
            button.backgroundColor = translated && text != nil ? backing : .clear
            button.setTitleColor(backing.perceivedBrightness > 0.5 ? .black : .white, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: max(11, min(48, r.height * 0.7)), weight: .medium)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.6
            button.layer.borderWidth = selectedID == region.id ? 3 : 0
            button.layer.borderColor = UIColor.systemBlue.cgColor
            button.accessibilityLabel = region.rawText + (text.map { ", " + $0 } ?? ", not translated")
            button.accessibilityHint = "Shows selectable original text and full translation"
        }
        c.fitIfNeeded()
        if c.selection != selectedID || c.previousCoveredHeight != coveredHeight {
            c.selection = selectedID
            c.previousCoveredHeight = coveredHeight
            if let selectedID, let button = c.buttons[selectedID] { c.reveal(button) }
        }
    }

    @MainActor final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scroll: CanvasScrollView?
        var canvas: UIView?
        var buttons: [String: UIButton] = [:]
        var onSelect: ((String) -> Void)?
        var selection: String?
        var coveredHeight: CGFloat = 0
        var previousCoveredHeight: CGFloat = 0
        private var viewport: CGSize = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

        func fitIfNeeded() {
            guard let scroll, let canvas, scroll.bounds.width > 0, scroll.bounds.height > 0,
                  viewport != scroll.bounds.size else { return }
            viewport = scroll.bounds.size
            let scale = min(scroll.bounds.width / canvas.bounds.width, scroll.bounds.height / canvas.bounds.height)
            scroll.minimumZoomScale = scale
            scroll.maximumZoomScale = max(scale * 8, 2)
            scroll.setZoomScale(scale, animated: false)
            center()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { center() }

        private func center() {
            guard let scroll else { return }
            scroll.contentInset = UIEdgeInsets(top: max(0, (scroll.bounds.height - scroll.contentSize.height) / 2),
                                               left: max(0, (scroll.bounds.width - scroll.contentSize.width) / 2),
                                               bottom: coveredHeight, right: 0)
        }

        func reveal(_ button: UIButton) {
            guard let scroll, let canvas else { return }
            center()
            let rect = canvas.convert(button.frame, to: scroll)
            let bottom = scroll.contentOffset.y + scroll.bounds.height - coveredHeight - scroll.safeAreaInsets.bottom - 12
            if rect.maxY > bottom {
                let target = scroll.contentOffset.y + rect.maxY - bottom
                let maximum = max(-scroll.contentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.contentInset.bottom)
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(target, maximum)), animated: false)
            }
            UIAccessibility.post(notification: .layoutChanged, argument: button)
        }
    }
}

final class CanvasScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); onLayout?() }
}

private extension UIImage {
    func backingColor(around rect: CGRect) -> UIColor {
        guard let image = cgImage else { return .systemBackground }
        let sample = CGRect(x: max(0, rect.minX - 4), y: max(0, rect.minY - 4), width: 3, height: 3)
        guard let crop = image.cropping(to: sample) else { return .systemBackground }
        var pixel: [UInt8] = [0, 0, 0, 255]
        let drawn = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return .systemBackground }
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }
}

private extension UIColor {
    var perceivedBrightness: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

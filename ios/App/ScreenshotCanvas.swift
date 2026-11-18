import SwiftUI
import TapLateCore

struct ScreenshotCanvas: UIViewRepresentable {
    let image: UIImage
    let regions: [TextRegion]
    let results: [String: RegionTranslation]
    let translated: Bool
    let selectedID: String?
    let coveredHeight: CGFloat
    let coveredTopHeight: CGFloat
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
        c.coveredTopHeight = coveredTopHeight
        let frames = Dictionary(uniqueKeysWithValues: regions.map { region in
            let r = region.rect
            return (region.id, CGRect(x: r.x, y: r.y, width: r.width, height: r.height))
        })
        let ids = Set(frames.keys)
        let overlapping = Self.overlappingIDs(in: frames)
        for id in Array(c.buttons.keys) where !ids.contains(id) { c.buttons.removeValue(forKey: id)?.removeFromSuperview() }
        for region in regions {
            guard let frame = frames[region.id] else { continue }
            let button: OverlayButton
            if let existing = c.buttons[region.id] { button = existing }
            else {
                button = OverlayButton()
                button.isAccessibilityElement = true
                button.accessibilityIdentifier = "region-" + region.id
                button.addAction(UIAction { [weak c] _ in c?.onSelect?(region.id) }, for: .touchUpInside)
                button.appearance = region.appearance ?? image.cgImage.flatMap { source in
                    ScreenshotInk.sample(source, in: frame).map {
                        TextAppearance(background: $0.background, foreground: $0.foreground)
                    }
                }
                c.canvas?.addSubview(button)
                c.buttons[region.id] = button
            }
            button.frame = frame
            let result = results[region.id]
            let text = result?.translation
            // Overlapping OCR rectangles can contain other labels. Keep those
            // original pixels visible and provide their translations on tap.
            if translated, !overlapping.contains(region.id), text != region.rawText,
               let result, text != nil, let appearance = button.appearance {
                button.backgroundColor = appearance.background.uiColor
                button.overlay.frame = button.bounds
                button.overlay.display(result, foreground: appearance.foreground)
            } else {
                button.backgroundColor = .clear
                button.overlay.attributedText = nil
            }
            button.layer.borderWidth = selectedID == region.id ? 3 : 0
            button.layer.borderColor = UIColor.systemBlue.cgColor
            button.isSelected = selectedID == region.id
            button.accessibilityLabel = region.rawText + (text.map { ", " + $0 } ?? ", not translated")
            button.accessibilityHint = "Shows selectable original text and full translation"
        }
        c.fitIfNeeded()
        if c.selection != selectedID || c.previousCoveredHeight != coveredHeight || c.previousTopHeight != coveredTopHeight {
            let formerSelection = c.selection
            let topObstructionShrank = coveredTopHeight < c.previousTopHeight
            c.selection = selectedID
            c.previousCoveredHeight = coveredHeight
            c.previousTopHeight = coveredTopHeight
            c.refreshInsets(preservingOffset: true, constrainTop: topObstructionShrank)
            if let selectedID, let button = c.buttons[selectedID] { c.reveal(button) }
            else if let formerSelection, let button = c.buttons[formerSelection] {
                UIAccessibility.post(notification: .layoutChanged, argument: button)
            }
        }
    }

    static func overlappingIDs(in frames: [String: CGRect]) -> Set<String> {
        let rows = frames.sorted { $0.value.minY < $1.value.minY }
        var overlapping: Set<String> = []
        for (index, current) in rows.enumerated() {
            for next in rows.dropFirst(index + 1) {
                if next.value.minY >= current.value.maxY { break }
                let intersection = current.value.intersection(next.value)
                if !intersection.isEmpty {
                    overlapping.insert(current.key)
                    overlapping.insert(next.key)
                }
            }
        }
        return overlapping
    }

    @MainActor final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scroll: CanvasScrollView?
        var canvas: UIView?
        var buttons: [String: OverlayButton] = [:]
        var onSelect: ((String) -> Void)?
        var selection: String?
        var coveredHeight: CGFloat = 0
        var coveredTopHeight: CGFloat = 0
        var previousCoveredHeight: CGFloat = 0
        var previousTopHeight: CGFloat = 0
        private var viewport: CGSize = .zero
        private var safeInsets: UIEdgeInsets = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

        func fitIfNeeded() {
            guard let scroll, let canvas, scroll.bounds.width > 0, scroll.bounds.height > 0,
                  viewport != scroll.bounds.size || safeInsets != scroll.safeAreaInsets else { return }
            viewport = scroll.bounds.size
            safeInsets = scroll.safeAreaInsets
            let availableWidth = max(1, scroll.bounds.width - safeInsets.left - safeInsets.right)
            let availableHeight = max(1, scroll.bounds.height - safeInsets.top - safeInsets.bottom)
            let scale = min(availableWidth / canvas.bounds.width, availableHeight / canvas.bounds.height)
            scroll.minimumZoomScale = scale
            scroll.maximumZoomScale = max(scale * 8, 2)
            scroll.setZoomScale(scale, animated: false)
            refreshInsets(preservingOffset: false)
            scroll.contentOffset = CGPoint(x: -scroll.contentInset.left, y: -scroll.contentInset.top)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { refreshInsets(preservingOffset: false) }

        func refreshInsets(preservingOffset: Bool, constrainTop: Bool = false) {
            guard let scroll else { return }
            var offset = scroll.contentOffset
            let safe = scroll.safeAreaInsets
            let vertical = max(0, (scroll.bounds.height - safe.top - safe.bottom - scroll.contentSize.height) / 2)
            let horizontal = max(0, (scroll.bounds.width - safe.left - safe.right - scroll.contentSize.width) / 2)
            scroll.contentInset = UIEdgeInsets(top: safe.top + vertical + coveredTopHeight,
                                               left: safe.left + horizontal,
                                               bottom: safe.bottom + vertical + coveredHeight,
                                               right: safe.right + horizontal)
            if preservingOffset {
                // The former status banner may have left the canvas above its new scroll limit.
                if constrainTop { offset.y = max(offset.y, -scroll.contentInset.top) }
                scroll.setContentOffset(offset, animated: false)
            }
        }

        func reveal(_ button: UIButton) {
            guard let scroll, let canvas else { return }
            refreshInsets(preservingOffset: true)
            let rect = canvas.convert(button.frame, to: scroll)
            let top = scroll.contentOffset.y + scroll.safeAreaInsets.top + coveredTopHeight + 12
            let bottom = scroll.contentOffset.y + scroll.bounds.height - coveredHeight - scroll.safeAreaInsets.bottom - 12
            var target = scroll.contentOffset
            if rect.maxY > bottom { target.y += rect.maxY - bottom }
            if rect.minY < top { target.y -= top - rect.minY }
            let left = scroll.contentOffset.x + scroll.safeAreaInsets.left + 8
            let right = scroll.contentOffset.x + scroll.bounds.width - scroll.safeAreaInsets.right - 8
            if rect.maxX > right { target.x += rect.maxX - right }
            if rect.minX < left { target.x -= left - rect.minX }
            target.y = min(max(target.y, -scroll.contentInset.top), max(-scroll.contentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.contentInset.bottom))
            target.x = min(max(target.x, -scroll.contentInset.left), max(-scroll.contentInset.left, scroll.contentSize.width - scroll.bounds.width + scroll.contentInset.right))
            scroll.setContentOffset(target, animated: false)
            UIAccessibility.post(notification: .layoutChanged, argument: button)
        }
    }
}

final class CanvasScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            accessibilityValue = "viewport=\(bounds.size), content=\(contentSize), offset=\(contentOffset), inset=\(contentInset), safe=\(safeAreaInsets), zoom=\(zoomScale)"
        }
        #endif
    }
}

final class OverlayButton: UIButton {
    let overlay = OverlayTextLabel()
    var appearance: TextAppearance?

    init() {
        super.init(frame: .zero)
        clipsToBounds = true
        overlay.isUserInteractionEnabled = false
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { nil }
}

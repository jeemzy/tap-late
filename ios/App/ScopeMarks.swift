import CoreGraphics
import TapLateCore

/// Two short, reversed color patterns at the same height. Fractions are in video coordinates.
enum ScopeMarks {
    static let aspect: CGFloat = 1.6
    private static let left: CGFloat = 0.08
    private static let right: CGFloat = 0.82
    private static let span: CGFloat = 0.10

    static func draw(in context: CGContext, size: CGSize, edge: ReadingEdge?) {
        context.saveGState()
        defer { context.restoreGState() }
        for (x, startsCyan) in [(left, true), (right, false)] {
            let box = CGRect(x: x * size.width, y: 0.45 * size.height,
                             width: span * size.width, height: 0.10 * size.height)
            context.setFillColor(gray: 0.08, alpha: 1)
            context.fill(box.insetBy(dx: -size.width * 0.006, dy: -size.height * 0.01))
            for i in 0..<3 {
                let cyan = i.isMultiple(of: 2) == startsCyan
                context.setFillColor(red: cyan ? 0 : 1, green: cyan ? 1 : 0, blue: 1, alpha: 1)
                context.fill(CGRect(x: box.minX + CGFloat(i) * box.width / 3, y: box.minY,
                                    width: box.width / 3, height: box.height))
            }
        }
        guard let edge else { return }
        let tip = edge == .above ? size.height * 0.014 : size.height * 0.986
        let base = tip + (edge == .above ? 1 : -1) * size.height * 0.075
        context.move(to: CGPoint(x: size.width * 0.5, y: tip))
        context.addLine(to: CGPoint(x: size.width * 0.46, y: base))
        context.addLine(to: CGPoint(x: size.width * 0.54, y: base))
        context.closePath()
        context.setFillColor(gray: 1, alpha: 1)
        context.setStrokeColor(gray: 0.1, alpha: 1)
        context.setLineWidth(max(1, size.height * 0.008))
        context.drawPath(using: .fillStroke)
    }

    private struct Run {
        let color: Int
        let x: Int
        let end: Int
        var length: Int { end - x }
    }

    /// RGBA scanlines, top to bottom, already oriented and reduced for background CPU use.
    static func window(rgba: [UInt8], width: Int, height: Int) -> CGRect? {
        var rows: [(x: CGFloat, width: CGFloat, y: Int)] = []
        for y in 0..<height {
            var runs: [Run] = []
            var color = 0, start = 0
            for x in 0...width {
                var next = 0
                if x < width {
                    let i = (y * width + x) * 4
                    let r = Int(rgba[i]), g = Int(rgba[i + 1]), b = Int(rgba[i + 2])
                    if b > 155 {
                        if g > 150 && g - r > 85 && b - r > 70 { next = 1 }
                        if r > 150 && r - g > 85 && b - g > 70 { next = 2 }
                    }
                }
                if color != next {
                    if color != 0 && x - start >= 2 { runs.append(Run(color: color, x: start, end: x)) }
                    start = x
                    color = next
                }
            }
            guard runs.count >= 6 else { continue }
            var marks: [(center: CGFloat, size: CGFloat, color: Int)] = []
            for i in 2..<runs.count {
                let a = runs[i - 2], b = runs[i - 1], c = runs[i]
                guard a.color == c.color, a.color != b.color, b.x - a.end <= 2, c.x - b.end <= 2,
                      max(a.length, b.length, c.length) <= 2 * min(a.length, b.length, c.length) else { continue }
                marks.append((CGFloat(a.x + c.end) / 2, CGFloat(c.end - a.x), a.color))
            }
            for a in marks where a.color == 1 {
                for b in marks where b.color == 2 && b.center > a.center {
                    let w = (b.center - a.center) / (right - left)
                    let expected = w * span
                    guard w >= 60, w <= CGFloat(width) + 2,
                          abs(a.size - expected) <= expected * 0.22 + 1,
                          abs(b.size - expected) <= expected * 0.22 + 1 else { continue }
                    let origin = a.center - w * (left + span / 2)
                    if let first = rows.first, abs(first.x - origin) > 3 || abs(first.width - w) > 4 { return nil }
                    rows.append((origin, w, y))
                }
            }
        }
        guard let first = rows.first, let last = rows.last else { return nil }
        let h = first.width / aspect
        let measured = CGFloat(last.y - first.y + 1)
        guard abs(measured - h * 0.10) <= max(2, h * 0.035), CGFloat(rows.count) >= measured * 0.8 else { return nil }
        return CGRect(x: first.x, y: CGFloat(first.y + last.y + 1) / 2 - h / 2, width: first.width, height: h)
    }
}

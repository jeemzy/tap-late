import CoreGraphics
import TapLateCore

enum ScopeBorder {
    // In the 480-pixel-wide PiP frame the green rim is four pixels wide,
    // with a two-pixel dark keyline between it and the reading area.
    static let rim: CGFloat = 4.0 / 480
    static let inset: CGFloat = 6.0 / 480

    static func draw(in ctx: CGContext, size: CGSize, edge: ReadingEdge?) {
        let rect = CGRect(origin: .zero, size: size)
        let thickness = size.width * rim
        ctx.setFillColor(red: 0.13, green: 0.61, blue: 0.36, alpha: 1)
        ctx.fill(rect)
        if let edge {
            ctx.setFillColor(red: 0.17, green: 0.68, blue: 0.41, alpha: 1)
            let y = edge == .above ? 0 : size.height - thickness
            ctx.fill(CGRect(x: 0, y: y, width: size.width, height: thickness))
        }
        ctx.setFillColor(gray: 0.025, alpha: 1)
        ctx.fill(rect.insetBy(dx: thickness, dy: thickness))
    }
}

/// Upright, downsampled screen coordinates. Match the four sides and their
/// inward-facing keylines. System PiP rounding can clip every corner.
struct ScopeBorderDetector {
    private let width: Int
    private let height: Int
    private let mask: [UInt8]

    init(rgba: [UInt8], width: Int, height: Int) {
        self.width = width
        self.height = height
        var labels = [UInt8](repeating: 0, count: width * height)
        for i in labels.indices {
            let r = Int(rgba[4*i]), g = Int(rgba[4*i+1]), b = Int(rgba[4*i+2])
            if (116...199).contains(g), r < 89, (46...139).contains(b), g - r > 66, g - b > 36 {
                labels[i] = 1
            } else if max(r, g, b) < 68, max(r, g, b) - min(r, g, b) < 36 {
                labels[i] = 2
            }
        }
        mask = labels
    }

    private func hits(_ value: UInt8, x: Int, y: Int, verticalSide: Bool) -> Bool {
        for delta in -1...1 {
            let px = verticalSide ? x + delta : x
            let py = verticalSide ? y : y + delta
            if px >= 0, py >= 0, px < width, py < height, mask[py * width + px] == value { return true }
        }
        return false
    }

    private func matches(_ rect: CGRect, requiredSides: Int) -> Bool {
        guard rect.width >= 64, rect.height >= 40,
              abs(rect.width / rect.height - 1.6) < 0.055,
              CGRect(x: 0, y: 0, width: width, height: height).contains(rect) else { return false }
        let rimDepth = ScopeBorder.rim / 2 * rect.width
        let lineDepth = (ScopeBorder.rim + ScopeBorder.inset) / 2 * rect.width
        var confirmedSides = 0
        var linedSides = 0
        for side in 0..<4 {
            let vertical = side < 2
            let start = side.isMultiple(of: 2)
            let outer = vertical ? (start ? rect.minX : rect.maxX) : (start ? rect.minY : rect.maxY)
            let direction: CGFloat = start ? 1 : -1
            let rim = Int(floor(outer + direction * rimDepth))
            let line = Int(floor(outer + direction * lineDepth))
            var green = 0, dark = 0
            for fraction: CGFloat in [0.23, 0.41, 0.59, 0.77] {
                let along = Int(vertical ? rect.minY + rect.height * fraction : rect.minX + rect.width * fraction)
                if hits(1, x: vertical ? rim : along, y: vertical ? along : rim, verticalSide: vertical) { green += 1 }
                if hits(2, x: vertical ? line : along, y: vertical ? along : line, verticalSide: vertical) { dark += 1 }
            }
            if green >= 3 { confirmedSides += 1 }
            if dark >= 2 { linedSides += 1 }
        }
        return confirmedSides >= requiredSides && linedSides >= 3
    }

    func window(previous: CGRect?) -> CGRect? {
        // Once acquired, three matching sides suffice while system controls cover an edge.
        if let previous, matches(previous, requiredSides: 3) { return previous }
        let maxRim = max(3, width / 65 + 2)
        var columnRuns: [Int: [Range<Int>]] = [:]
        func runs(count: Int, offset: Int, step: Int) -> [Range<Int>] {
            var result: [Range<Int>] = []
            var index = 0
            while index < count {
                if mask[offset + index * step] != 1 { index += 1; continue }
                let start = index
                repeat { index += 1 } while index < count && mask[offset + index * step] == 1
                if index - start <= maxRim { result.append(start..<index) }
            }
            return result
        }
        for y in stride(from: 6, to: height, by: 8) {
            let sides = runs(count: width, offset: y * width, step: 1)
            for (i, left) in sides.enumerated() {
                for right in sides.dropFirst(i + 1) {
                    let w = right.upperBound - left.lowerBound
                    guard w >= 64 else { continue }
                    let h = Double(w) / 1.6
                    let expectedRim = Double(w) * ScopeBorder.rim
                    guard abs(Double(left.count) - expectedRim) < 2,
                          abs(Double(right.count) - expectedRim) < 2 else { continue }
                    let center = (left.lowerBound + right.upperBound) / 2
                    if columnRuns[center] == nil { columnRuns[center] = runs(count: height, offset: center, step: width) }
                    let bands = columnRuns[center] ?? []
                    for top in bands where top.upperBound < y && Double(y - top.lowerBound) < h {
                        let bottomY = Double(top.lowerBound) + h
                        for bottom in bands where bottom.lowerBound > y && abs(Double(bottom.upperBound) - bottomY) <= 3 {
                            let rect = CGRect(x: left.lowerBound, y: top.lowerBound, width: w, height: bottom.upperBound - top.lowerBound)
                            if matches(rect, requiredSides: 4) { return rect }
                        }
                    }
                }
            }
        }
        return nil
    }
}

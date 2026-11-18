import CoreGraphics
import Foundation
import TapLateCore

struct ScreenshotInk {
    let background: TextInk
    let foreground: TextInk
    let hasMixedInk: Bool

    static func sample(_ image: CGImage, in rect: CGRect, background knownBackground: TextInk? = nil) -> Self? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = rect.integral.intersection(bounds)
        guard !cropRect.isEmpty, let crop = image.cropping(to: cropRect) else { return nil }
        let width = min(crop.width, 192)
        let height = min(crop.height, 40)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var palette: [Int: Bucket] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] >= 245 {
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            let key = (red >> 4) * 256 + (green >> 4) * 16 + (blue >> 4)
            palette[key, default: Bucket()].add(red: red, green: green, blue: blue)
        }
        let buckets = palette.sorted { $0.key < $1.key }.map(\.value)
        guard let background = knownBackground ?? buckets.max(by: { $0.count < $1.count })?.ink else { return nil }
        let candidates = buckets.filter { $0.count >= 3 && $0.ink.distanceSquared(to: background) >= 18 * 18 }
        guard let foreground = candidates.max(by: {
            $0.count * $0.ink.distanceSquared(to: background) < $1.count * $1.ink.distanceSquared(to: background)
        })?.ink else { return nil }
        // Antialiasing creates blends along one color ramp. A second ink must
        // contribute visible pixels away from that ramp.
        let mixedPixels = candidates.reduce(0) { count, bucket in
            count + (bucket.ink.distanceFromRamp(background, foreground) >= 34 ? bucket.count : 0)
        }
        return Self(background: background, foreground: foreground,
                    hasMixedInk: mixedPixels >= max(5, width * height / 180))
    }

    private struct Bucket {
        var count = 0
        var red = 0
        var green = 0
        var blue = 0

        mutating func add(red: Int, green: Int, blue: Int) {
            count += 1
            self.red += red
            self.green += green
            self.blue += blue
        }

        var ink: TextInk {
            TextInk(red: UInt8(red / count), green: UInt8(green / count), blue: UInt8(blue / count))
        }
    }
}

extension TextInk {
    func distanceSquared(to other: Self) -> Int {
        let r = Int(red) - Int(other.red)
        let g = Int(green) - Int(other.green)
        let b = Int(blue) - Int(other.blue)
        return r * r + g * g + b * b
    }

    fileprivate func distanceFromRamp(_ background: Self, _ foreground: Self) -> Double {
        let r = Double(red) - Double(background.red)
        let g = Double(green) - Double(background.green)
        let b = Double(blue) - Double(background.blue)
        let dr = Double(foreground.red) - Double(background.red)
        let dg = Double(foreground.green) - Double(background.green)
        let db = Double(foreground.blue) - Double(background.blue)
        let scale = max(0, min(1, (r * dr + g * dg + b * db) / (dr * dr + dg * dg + db * db)))
        let residualR = r - scale * dr
        let residualG = g - scale * dg
        let residualB = b - scale * db
        return sqrt(residualR * residualR + residualG * residualG + residualB * residualB)
    }
}

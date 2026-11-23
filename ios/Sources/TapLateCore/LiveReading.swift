import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum LiveReadingScope: String, CaseIterable, Sendable {
    case zone = "Reading zone"
    case whole = "Whole screen"
}

public enum ReadingZone: String, CaseIterable, Sendable {
    case top = "Top"
    case middle = "Middle"
    case bottom = "Bottom"

    /// Coordinates are in upright image pixels, measured from the top left.
    public func crop(scope: LiveReadingScope, width: Int, height: Int) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        guard scope == .zone, height >= 3 else { return full }
        let index = Self.allCases.firstIndex(of: self) ?? 1
        let start = index * height / 3
        let end = (index + 1) * height / 3
        return CGRect(x: 0, y: start, width: width, height: end - start)
    }
}

/// A recognition or translation result belongs only to the frame that requested it.
public struct LiveFrameSequence: Sendable {
    public private(set) var generation = 0
    private var signature: [UInt8] = []
    private var width = 0
    private var height = 0

    public init() {}

    public mutating func admit(signature next: [UInt8], width: Int, height: Int) -> Bool {
        guard next != signature || self.width != width || self.height != height else { return false }
        generation += 1
        signature = next
        self.width = width
        self.height = height
        return true
    }

    public func accepts(_ ticket: Int) -> Bool { generation == ticket }
}

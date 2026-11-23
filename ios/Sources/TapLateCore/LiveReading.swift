import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum LiveReadingScope: String, CaseIterable, Sendable {
    // Keep the persisted value used by the original fixed-zone preference.
    case near = "Reading zone"
    case whole = "Whole screen"

    public var title: String { self == .near ? "Near the window" : rawValue }
}

public enum ReadingEdge: Sendable { case above, below }

public struct NearbyArea: Equatable, Sendable {
    public let crop: CGRect
    public let edge: ReadingEdge

    /// Upright pixels measured from the top left. Leave clearance for the PiP shadow.
    public init?(window: CGRect, screen: CGSize, previous: ReadingEdge?) {
        let bounds = CGRect(origin: .zero, size: screen)
        guard window.width > 0, window.height > 0, bounds.insetBy(dx: -3, dy: -3).contains(window) else { return nil }
        let fraction = window.midY / screen.height
        edge = fraction < 0.45 ? .below : fraction > 0.55 ? .above : previous ?? (fraction <= 0.5 ? .below : .above)
        let gap = max(4, (window.width * 0.035).rounded())
        let room = edge == .below ? screen.height - window.maxY - gap : window.minY - gap
        let height = floor(min(window.height, room))
        guard height >= 12 else { return nil }
        let width = floor(min(window.width, height * 1.6))
        let x = min(max(0, (window.midX - width / 2).rounded()), screen.width - width)
        let y = edge == .below ? ceil(window.maxY + gap) : floor(window.minY - gap - height)
        crop = CGRect(x: x, y: y, width: width, height: height)
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

    public mutating func invalidate() {
        generation += 1
        signature.removeAll(keepingCapacity: true)
        width = 0
        height = 0
    }

    public func accepts(_ ticket: Int) -> Bool { generation == ticket }
}

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import TapLateCore

struct LiveReadingTests {
    @Test func nearbyAreaUsesWindowWidthAndKeepsItsEdgeThroughTheMidpoint() throws {
        let screen = CGSize(width: 400, height: 820)
        func area(_ x: Int, _ y: Int, previous: ReadingEdge? = nil) throws -> NearbyArea {
            try #require(NearbyArea(window: CGRect(x: x, y: y, width: 160, height: 100), screen: screen, previous: previous))
        }
        let high = try area(80, 20)
        #expect(high.edge == .below)
        #expect(high.crop.minY > 120 && high.crop.width == 160 && high.crop.minX == 80)
        let middle = try area(130, 370, previous: high.edge)
        #expect(middle.edge == .below)
        let low = try area(130, 670, previous: middle.edge)
        #expect(low.edge == .above && low.crop.maxY < 670)
        let back = try area(130, 350, previous: low.edge)
        #expect(back.edge == .above)
        #expect(NearbyArea(window: CGRect(x: -75, y: 10, width: 160, height: 100), screen: screen, previous: nil) == nil)
        #expect(LiveReadingScope(rawValue: "Reading zone") == .near)
        #expect(LiveReadingScope(rawValue: "Whole screen") == .whole)
    }

    @Test func changedFrameRejectsLateResultsAndRotationInvalidatesIdenticalPixels() {
        var frames = LiveFrameSequence()
        let admitted = frames.admit(signature: [1, 2], width: 20, height: 30)
        #expect(admitted)
        let first = frames.generation
        let repeated = frames.admit(signature: [1, 2], width: 20, height: 30)
        #expect(!repeated)
        #expect(frames.accepts(first))
        let scrolled = frames.admit(signature: [1, 3], width: 20, height: 30)
        #expect(scrolled)
        #expect(!frames.accepts(first))
        let rotated = frames.admit(signature: [1, 3], width: 30, height: 20)
        #expect(rotated)
        let last = frames.generation
        frames.invalidate()
        #expect(!frames.accepts(last))
        let reacquired = frames.admit(signature: [1, 3], width: 30, height: 20)
        #expect(reacquired)
    }
}

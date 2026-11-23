import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import TapLateCore

struct LiveReadingTests {
    @Test func zoneThirdsCoverPortraitAndLandscapeWithoutGaps() {
        for (width, height) in [(430, 931), (931, 430)] {
            var y: CGFloat = 0
            for zone in ReadingZone.allCases {
                let rect = zone.crop(scope: .zone, width: width, height: height)
                #expect(rect.minY == y)
                #expect(rect.width == CGFloat(width))
                y = rect.maxY
                #expect(zone.crop(scope: .whole, width: width, height: height) == CGRect(x: 0, y: 0, width: width, height: height))
            }
            #expect(y == CGFloat(height))
        }
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
    }
}

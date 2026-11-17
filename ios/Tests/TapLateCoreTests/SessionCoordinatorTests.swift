import Foundation
import Testing
@testable import TapLateCore

@MainActor final class MemoryRepository: SessionRepository {
    var records: [ScreenshotSession] = []
    var images: [UUID: Data] = [:]
    var rejectWrites = false

    func load() -> [ScreenshotSession] { records }
    func insert(_ session: ScreenshotSession, image: Data) throws {
        if rejectWrites { throw CocoaError(.fileWriteNoPermission) }
        records.append(session)
        images[session.id] = image
    }
}

@Suite @MainActor struct SessionCoordinatorTests {
    @Test func `capture is persisted before returning and survives coordinator restart`() throws {
        let repository = MemoryRepository()
        let coordinator = try SessionCoordinator(repository: repository)
        let image = CapturedImage(data: Data([1, 2, 3]), width: 1320, height: 2868)
        let id = try coordinator.capture(image)

        #expect(repository.images[id] == Data([1, 2, 3]))
        let restored = try SessionCoordinator(repository: repository)
        #expect(restored.sessions.map(\.id) == [id])
        #expect(restored.sessions.first?.width == 1320)
        #expect(restored.sessions.first?.height == 2868)
    }
}

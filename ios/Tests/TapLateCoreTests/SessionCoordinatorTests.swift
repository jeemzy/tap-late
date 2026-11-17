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
    func update(_ session: ScreenshotSession) throws {
        if rejectWrites { throw CocoaError(.fileWriteNoPermission) }
        guard let index = records.firstIndex(where: { $0.id == session.id }) else { throw CocoaError(.fileNoSuchFile) }
        records[index] = session
    }
}

@MainActor final class FakeEngine: ScreenshotEngine {
    var started: [UUID] = []
    var recognized: [UUID] = []
    var configurationSnapshots: [EngineConfiguration] = []
    var translations: [[String]] = []
    let regions = [
        TextRegion(id: "r001", rawText: "蓝色", confidence: 0.99, rect: PixelRect(x: 10, y: 20, width: 80, height: 30)),
        TextRegion(id: "r002", rawText: "蓝色", confidence: 0.95, rect: PixelRect(x: 10, y: 60, width: 80, height: 30))
    ]
    func recognize(_ session: ScreenshotSession) async throws -> [TextRegion] {
        started.append(session.id); recognized.append(session.id)
        return regions
    }
    func translate(_ regions: [TextRegion], configuration: EngineConfiguration,
                   emit: @MainActor (String, RegionTranslation) throws -> Void) async throws {
        configurationSnapshots.append(configuration)
        translations.append(regions.map(\.id))
        for region in regions { try emit(region.id, RegionTranslation(source: region.rawText, translation: "Blue")) }
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

    @Test func `rapid captures translate in capture order with separate repeated regions`() async throws {
        let repository = MemoryRepository()
        let engine = FakeEngine()
        let coordinator = try SessionCoordinator(repository: repository, engine: engine)
        coordinator.setActive(true)
        let image = CapturedImage(data: Data([1]), width: 1320, height: 2868)
        let ids = try (0..<3).map { _ in try coordinator.capture(image) }
        await coordinator.waitUntilIdle()

        #expect(engine.started == ids)
        #expect(coordinator.sessions.allSatisfy { $0.attempt.state == .ready })
        #expect(coordinator.sessions.allSatisfy { $0.displayedResults.count == 2 })
        let restored = try SessionCoordinator(repository: repository)
        #expect(restored.sessions.allSatisfy { $0.completeResults?.count == 2 })
    }
}

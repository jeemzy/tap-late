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
    var failAfterOne = false
    var holdAfterOne = false
    var isHolding = false
    var renderedText = "Blue"
    private var held: CheckedContinuation<Void, Never>?
    var regions = [
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
        for region in regions {
            try emit(region.id, RegionTranslation(source: region.rawText, translation: renderedText))
            if holdAfterOne {
                isHolding = true
                await withCheckedContinuation { held = $0 }
                isHolding = false
            }
            if failAfterOne { throw CocoaError(.fileReadUnknown) }
        }
    }
    func releaseHeld() {
        holdAfterOne = false
        held?.resume()
        held = nil
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

    @Test func `retry keeps completed regions and does not run OCR again`() async throws {
        let repository = MemoryRepository()
        let engine = FakeEngine()
        engine.failAfterOne = true
        let coordinator = try SessionCoordinator(repository: repository, engine: engine)
        coordinator.setActive(true)
        let id = try coordinator.capture(CapturedImage(data: Data([1]), width: 1320, height: 2868))
        await coordinator.waitUntilIdle()
        #expect(coordinator.sessions.first?.attempt.state == .failed)
        #expect(coordinator.sessions.first?.displayedResults["r001"]?.translation == "Blue")

        engine.failAfterOne = false
        try coordinator.retry(id)
        await coordinator.waitUntilIdle()
        #expect(engine.recognized == [id])
        #expect(engine.translations == [["r001", "r002"], ["r002"]])
        #expect(coordinator.sessions.first?.completeResults?.count == 2)
        #expect(coordinator.sessions.first?.attempt.state == .ready)
    }

    @Test func `suspension checkpoints work and a new coordinator resumes only unfinished regions`() async throws {
        let repository = MemoryRepository()
        let engine = FakeEngine()
        engine.holdAfterOne = true
        let coordinator = try SessionCoordinator(repository: repository, engine: engine)
        coordinator.setActive(true)
        let id = try coordinator.capture(CapturedImage(data: Data([1]), width: 1320, height: 2868))
        for _ in 0..<1000 where !engine.isHolding { await Task.yield() }
        try #require(engine.isHolding)
        coordinator.setActive(false)
        engine.releaseHeld()
        await coordinator.waitUntilIdle()
        #expect(coordinator.sessions.first?.attempt.state == .queued)
        #expect(coordinator.sessions.first?.attempt.results.keys.sorted() == ["r001"])

        let nextEngine = FakeEngine()
        let restored = try SessionCoordinator(repository: repository, engine: nextEngine)
        restored.setActive(true)
        await restored.waitUntilIdle()
        #expect(nextEngine.recognized.isEmpty)
        #expect(nextEngine.translations == [["r002"]])
        #expect(restored.sessions.first?.id == id)
        #expect(restored.sessions.first?.attempt.state == .ready)
    }

    @Test func `retranslation keeps old complete result and uses the attempt settings until replacement succeeds`() async throws {
        let repository = MemoryRepository()
        let engine = FakeEngine()
        let coordinator = try SessionCoordinator(repository: repository, engine: engine)
        coordinator.setActive(true)
        let id = try coordinator.capture(CapturedImage(data: Data([1]), width: 1320, height: 2868))
        await coordinator.waitUntilIdle()

        let override = EngineConfiguration(engine: .openAI, model: "test-model", reasoning: "low")
        engine.renderedText = "Navy"
        engine.failAfterOne = true
        try coordinator.retry(id, configuration: override)
        coordinator.defaultConfiguration = EngineConfiguration(engine: .appleHighFidelity)
        await coordinator.waitUntilIdle()
        #expect(coordinator.sessions.first?.displayedResults["r001"]?.translation == "Blue")
        #expect(coordinator.sessions.first?.displayedResults["r002"]?.translation == "Blue")
        #expect(engine.configurationSnapshots.last == override)

        engine.failAfterOne = false
        try coordinator.retry(id)
        await coordinator.waitUntilIdle()
        #expect(coordinator.sessions.first?.displayedResults.values.allSatisfy { $0.translation == "Navy" } == true)
        #expect(engine.configurationSnapshots.last == override)
        #expect(coordinator.defaultConfiguration.engine == .appleHighFidelity)
        #expect(engine.recognized == [id])
    }

    @Test func `original-only installation proof captures remain readable after app update`() throws {
        let legacy = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","createdAt":0,"width":1320,"height":2868}
        """.utf8)
        let session = try JSONDecoder().decode(ScreenshotSession.self, from: legacy)
        #expect(session.width == 1320 && session.height == 2868)
        #expect(session.attempt.state == .queued)
        #expect(session.regions.isEmpty && !session.recognized)
    }
}

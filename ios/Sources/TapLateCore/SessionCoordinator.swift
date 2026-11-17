import Foundation
import Observation

public struct CapturedImage: Sendable {
    public let data: Data
    public let width: Int
    public let height: Int

    public init(data: Data, width: Int, height: Int) {
        self.data = data
        self.width = width
        self.height = height
    }
}

public struct ScreenshotSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let width: Int
    public let height: Int
    public var regions: [TextRegion] = []
    public var recognized = false
    public var attempt: TranslationAttempt
    public var completeResults: [String: RegionTranslation]?

    public var displayedResults: [String: RegionTranslation] { completeResults ?? attempt.results }

    public init(id: UUID, createdAt: Date, width: Int, height: Int, attempt: TranslationAttempt) {
        self.id = id; self.createdAt = createdAt; self.width = width; self.height = height; self.attempt = attempt
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, width, height, regions, recognized, attempt, completeResults
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        width = try values.decode(Int.self, forKey: .width)
        height = try values.decode(Int.self, forKey: .height)
        regions = try values.decodeIfPresent([TextRegion].self, forKey: .regions) ?? []
        recognized = try values.decodeIfPresent(Bool.self, forKey: .recognized) ?? false
        attempt = try values.decodeIfPresent(TranslationAttempt.self, forKey: .attempt) ?? TranslationAttempt(configuration: .init(), order: 0)
        completeResults = try values.decodeIfPresent([String: RegionTranslation].self, forKey: .completeResults)
    }
}

@MainActor public protocol SessionRepository {
    func load() throws -> [ScreenshotSession]
    func insert(_ session: ScreenshotSession, image: Data) throws
    func update(_ session: ScreenshotSession) throws
}

@MainActor @Observable public final class SessionCoordinator {
    public private(set) var sessions: [ScreenshotSession]
    private let repository: any SessionRepository
    private let engine: (any ScreenshotEngine)?
    public var defaultConfiguration = EngineConfiguration()
    public private(set) var storageError: String?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var workerID: UUID?
    private var active = false

    public init(repository: any SessionRepository, engine: (any ScreenshotEngine)? = nil) throws {
        self.repository = repository
        self.engine = engine
        self.sessions = try repository.load()
        try recoverInterruptedWork()
    }

    @discardableResult public func capture(_ image: CapturedImage, override: EngineConfiguration? = nil) throws -> UUID {
        guard !image.data.isEmpty, image.width > 0, image.height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let order = (sessions.map { $0.attempt.order }.max() ?? 0) + 1
        let attempt = TranslationAttempt(configuration: override ?? defaultConfiguration, order: order)
        let session = ScreenshotSession(id: UUID(), createdAt: Date(), width: image.width, height: image.height, attempt: attempt)
        try repository.insert(session, image: image.data)
        sessions.append(session)
        startWorker()
        return session.id
    }

    public func setActive(_ active: Bool) {
        guard self.active != active else {
            if active { startWorker() }
            return
        }
        self.active = active
        do {
            if !active {
                generation += 1
                worker?.cancel()
            }
            try recoverInterruptedWork()
            storageError = nil
            if active { startWorker() }
        } catch {
            storageError = "Progress could not be saved. Free some storage, then reopen tap-late."
            self.active = false
        }
    }

    public func waitUntilIdle() async {
        while let worker { await worker.value }
    }

    @discardableResult public func importImage(
        _ data: Data, override: EngineConfiguration? = nil,
        normalize: @escaping @MainActor @Sendable (Data) async throws -> CapturedImage
    ) async throws -> UUID {
        let image = try await normalize(data)
        return try capture(image, override: override)
    }

    public func retry(_ id: UUID, configuration: EngineConfiguration? = nil) throws {
        guard var session = sessions.first(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        let chosen = configuration ?? session.attempt.configuration
        let keepPartial = session.attempt.state != .ready && chosen == session.attempt.configuration
        let results = keepPartial ? session.attempt.results : [:]
        let order = (sessions.map { $0.attempt.order }.max() ?? 0) + 1
        session.attempt = TranslationAttempt(configuration: chosen, order: order)
        session.attempt.results = results
        try save(session)
        startWorker()
    }

    private func save(_ session: ScreenshotSession) throws {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { throw CancellationError() }
        try repository.update(session)
        sessions[index] = session
    }

    private func current(_ id: UUID, attempt: UUID, generation: Int) throws -> ScreenshotSession {
        guard active, self.generation == generation,
              let session = sessions.first(where: { $0.id == id }), session.attempt.id == attempt else {
            throw CancellationError()
        }
        return session
    }

    private func startWorker() {
        guard active, engine != nil, worker == nil else { return }
        let token = generation
        let id = UUID()
        workerID = id
        worker = Task { [weak self] in
            guard let self else { return }
            while self.active, self.generation == token,
                  let next = self.sessions.filter({ $0.attempt.state == .queued }).min(by: { $0.attempt.order < $1.attempt.order }) {
                await self.process(next, generation: token)
            }
            if self.workerID == id {
                self.worker = nil
                self.workerID = nil
                if self.active, self.sessions.contains(where: { $0.attempt.state == .queued }) { self.startWorker() }
            }
        }
    }

    private func recoverInterruptedWork() throws {
        for var session in sessions where session.attempt.state == .recognizing || session.attempt.state == .translating {
            if session.attempt.configuration.engine == .openAI {
                session.attempt.state = .failed
                session.attempt.error = "The OpenAI request was interrupted and its outcome is unknown. Retry explicitly if needed."
            } else {
                session.attempt.state = .queued
                session.attempt.error = nil
            }
            try save(session)
        }
    }

    private func process(_ snapshot: ScreenshotSession, generation token: Int) async {
        guard let engine else { return }
        let id = snapshot.id, attemptID = snapshot.attempt.id
        do {
            var session = try current(id, attempt: attemptID, generation: token)
            if !session.recognized {
                session.attempt.state = .recognizing
                try save(session)
                let regions = try await engine.recognize(session)
                session = try current(id, attempt: attemptID, generation: token)
                let valid = regions.allSatisfy { region in
                    let r = region.rect
                    return !region.id.isEmpty && !region.rawText.isEmpty &&
                        [r.x, r.y, r.width, r.height, region.confidence].allSatisfy(\.isFinite) &&
                        r.x >= 0 && r.y >= 0 && r.width > 0 && r.height > 0 &&
                        r.x + r.width <= Double(session.width) + 0.01 && r.y + r.height <= Double(session.height) + 0.01
                }
                guard valid, Set(regions.map(\.id)).count == regions.count else { throw TranslationFailure.invalidRegions }
                session.regions = regions
                session.recognized = true
            }
            session.attempt.state = .translating
            try save(session)
            let remaining = session.regions.filter { session.attempt.results[$0.id]?.translation?.isEmpty != false }
            let expected = Set(remaining.map(\.id))
            var received = Set<String>()
            try await engine.translate(remaining, configuration: session.attempt.configuration) { regionID, result in
                guard expected.contains(regionID), received.insert(regionID).inserted else { throw TranslationFailure.invalidResponse }
                var updated = try self.current(id, attempt: attemptID, generation: token)
                updated.attempt.results[regionID] = result
                try self.save(updated)
            }
            session = try current(id, attempt: attemptID, generation: token)
            guard session.regions.allSatisfy({ session.attempt.results[$0.id]?.translation?.isEmpty == false }) else {
                throw TranslationFailure.invalidResponse
            }
            session.completeResults = session.attempt.results
            session.attempt.state = .ready
            session.attempt.error = nil
            try save(session)
        } catch is CancellationError {
            return
        } catch {
            guard var session = try? current(id, attempt: attemptID, generation: token) else { return }
            if case TranslationFailure.preparationRequired = error { session.attempt.state = .needsPreparation }
            else { session.attempt.state = .failed }
            session.attempt.error = error.localizedDescription
            do { try save(session) }
            catch {
                storageError = "Progress could not be saved. Free some storage, then reopen tap-late."
                active = false
            }
        }
    }
}

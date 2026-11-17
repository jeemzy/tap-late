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
    private var active = false

    public init(repository: any SessionRepository, engine: (any ScreenshotEngine)? = nil) throws {
        self.repository = repository
        self.engine = engine
        self.sessions = try repository.load()
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
        self.active = active
        if active { startWorker() }
    }

    public func waitUntilIdle() async {
        while let worker { await worker.value }
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
        worker = Task { [weak self] in
            guard let self else { return }
            while self.active, self.generation == token,
                  let next = self.sessions.filter({ $0.attempt.state == .queued }).min(by: { $0.attempt.order < $1.attempt.order }) {
                await self.process(next, generation: token)
            }
            if self.generation == token { self.worker = nil }
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

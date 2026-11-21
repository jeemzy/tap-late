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
    public var groupID: UUID?
    // Retains the burst's submission time when its newest image is individually deleted.
    public var lastGroupSubmission: Date?
    public var regions: [TextRegion] = []
    public var recognized = false
    public var attempt: TranslationAttempt
    public var completeResults: [String: RegionTranslation]?

    public var currencyChoices: [String: RegionCurrencyChoices] = [:]

    public func source(for region: TextRegion) -> String {
        if let source = displayedResults[region.id]?.source, !source.isEmpty { return source }
        return region.rawText
    }

    public var displayedResults: [String: RegionTranslation] { completeResults ?? attempt.results }

    public init(id: UUID, createdAt: Date, width: Int, height: Int, attempt: TranslationAttempt) {
        self.id = id; self.createdAt = createdAt; self.width = width; self.height = height; self.attempt = attempt
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, width, height, regions, recognized, attempt, completeResults, currencyChoices, groupID, lastGroupSubmission
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        groupID = try values.decodeIfPresent(UUID.self, forKey: .groupID)
        lastGroupSubmission = try values.decodeIfPresent(Date.self, forKey: .lastGroupSubmission)
        width = try values.decode(Int.self, forKey: .width)
        height = try values.decode(Int.self, forKey: .height)
        regions = try values.decodeIfPresent([TextRegion].self, forKey: .regions) ?? []
        recognized = try values.decodeIfPresent(Bool.self, forKey: .recognized) ?? false
        attempt = try values.decodeIfPresent(TranslationAttempt.self, forKey: .attempt) ?? TranslationAttempt(configuration: .init(), order: 0)
        currencyChoices = try values.decodeIfPresent([String: RegionCurrencyChoices].self, forKey: .currencyChoices) ?? [:]
        completeResults = try values.decodeIfPresent([String: RegionTranslation].self, forKey: .completeResults)
    }
}

@MainActor public protocol SessionRepository {
    func load() throws -> [ScreenshotSession]
    func insert(_ session: ScreenshotSession, image: Data) throws
    func update(_ session: ScreenshotSession) throws
    func remove(_ ids: Set<UUID>, retaining survivor: ScreenshotSession?) throws
    func cleanOrphanImages(keeping ids: Set<UUID>) throws
}

public struct HistoryGroup: Identifiable {
    public let id: UUID
    public let sessions: [ScreenshotSession]
    public var newest: Date { sessions.map { max($0.createdAt, $0.lastGroupSubmission ?? $0.createdAt) }.max() ?? .distantPast }
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
    @ObservationIgnored private var admissionTail: Task<UUID, any Error>?
    @ObservationIgnored private var admissionID: UUID?
    private var active = false
    private let clock: () -> Date
    private var processingID: UUID?

    public var groups: [HistoryGroup] {
        Dictionary(grouping: sessions, by: { $0.groupID ?? $0.id }).map { id, members in
            HistoryGroup(id: id, sessions: members.sorted { $0.createdAt > $1.createdAt })
        }.sorted { $0.newest > $1.newest }
    }

    public init(repository: any SessionRepository, engine: (any ScreenshotEngine)? = nil, clock: @escaping () -> Date = { Date() }) throws {
        self.repository = repository
        self.engine = engine
        self.clock = clock
        self.sessions = try repository.load().sorted { $0.createdAt < $1.createdAt }
        // Older payloads predate groups. Persist their original bursts before the first deletion.
        var previous: ScreenshotSession?
        for var session in sessions {
            if session.groupID == nil {
                session.groupID = Self.group(for: session.createdAt, after: previous) ?? session.id
                try save(session)
            }
            previous = session
        }
        try maintainHistory()
        try recoverInterruptedWork()
    }

    @discardableResult public func capture(_ image: CapturedImage, override: EngineConfiguration? = nil, receivedAt: Date? = nil) throws -> UUID {
        guard !image.data.isEmpty, image.width > 0, image.height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let order = (sessions.map { $0.attempt.order }.max() ?? 0) + 1
        let attempt = TranslationAttempt(configuration: override ?? defaultConfiguration, order: order)
        let date = receivedAt ?? clock()
        var session = ScreenshotSession(id: UUID(), createdAt: date, width: image.width, height: image.height, attempt: attempt)
        let latest = groups.first
        session.groupID = latest.flatMap { date.timeIntervalSince($0.newest) < 600 ? $0.id : nil } ?? session.id
        try repository.insert(session, image: image.data)
        sessions.append(session)
        startWorker()
        return session.id
    }

    private static func group(for date: Date, after previous: ScreenshotSession?) -> UUID? {
        guard let previous, date.timeIntervalSince(previous.createdAt) < 600 else { return nil }
        return previous.groupID
    }

    private func maintainHistory() throws {
        let now = clock()
        let expired = Set(groups.filter { now.timeIntervalSince($0.newest) >= 86_400 }.flatMap { $0.sessions.map(\.id) })
        if !expired.isEmpty { try remove(expired, retaining: nil) }
        try repository.cleanOrphanImages(keeping: Set(sessions.map(\.id)))
    }

    public func deleteSession(_ id: UUID) throws {
        guard let group = groups.first(where: { $0.sessions.contains(where: { $0.id == id }) }) else { return }
        var survivor = group.sessions.first(where: { $0.id != id })
        survivor?.lastGroupSubmission = group.newest
        try remove([id], retaining: survivor)
    }

    public func deleteGroup(_ id: UUID) throws {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        try remove(Set(group.sessions.map(\.id)), retaining: nil)
    }

    private func remove(_ ids: Set<UUID>, retaining survivor: ScreenshotSession?) throws {
        try repository.remove(ids, retaining: survivor)
        if let processingID, ids.contains(processingID) {
            generation += 1
            worker?.cancel()
        }
        sessions.removeAll { ids.contains($0.id) }
        if let survivor, let index = sessions.firstIndex(where: { $0.id == survivor.id }) { sessions[index] = survivor }
        try repository.cleanOrphanImages(keeping: Set(sessions.map(\.id)))
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
            if active { try maintainHistory() }
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
        let predecessor = admissionTail
        let configuration = override ?? defaultConfiguration
        let receivedAt = clock()
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            // A rejected earlier image must not prevent the next one from being admitted.
            if let predecessor { _ = try? await predecessor.value }
            guard let self else { throw CancellationError() }
            let image = try await normalize(data)
            return try self.capture(image, override: configuration, receivedAt: receivedAt)
        }
        admissionTail = task
        admissionID = token
        defer {
            if admissionID == token { admissionTail = nil; admissionID = nil }
        }
        return try await task.value
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

    public func chooseCurrency(_ currency: PriceCurrency, sessionID: UUID, regionID: String, source: String, amountID: Int) throws {
        guard var session = sessions.first(where: { $0.id == sessionID }),
              let region = session.regions.first(where: { $0.id == regionID }),
              session.source(for: region) == source,
              PriceAmount.candidates(in: source).contains(where: { $0.id == amountID }) else { throw CocoaError(.fileNoSuchFile) }
        var choices = session.currencyChoices[regionID] ?? RegionCurrencyChoices(source: source, currencies: [:])
        choices.currencies[amountID] = currency
        session.currencyChoices[regionID] = choices
        try save(session)
    }

    private func save(_ snapshot: ScreenshotSession) throws {
        var session = snapshot
        for (id, choices) in snapshot.currencyChoices {
            if let region = session.regions.first(where: { $0.id == id }), session.source(for: region) == choices.source { continue }
            session.currencyChoices.removeValue(forKey: id)
        }
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
                self.processingID = next.id
                await self.process(next, generation: token)
                self.processingID = nil
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
                switch result.outcome {
                case .translated:
                    guard result.translation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { throw TranslationFailure.invalidResponse }
                case .unreadable:
                    guard result.translation == nil else { throw TranslationFailure.invalidResponse }
                }
                var updated = try self.current(id, attempt: attemptID, generation: token)
                updated.attempt.results[regionID] = result
                try self.save(updated)
            }
            session = try current(id, attempt: attemptID, generation: token)
            guard session.regions.allSatisfy({ session.attempt.results[$0.id] != nil }) else {
                throw TranslationFailure.invalidResponse
            }
            if session.attempt.results.values.contains(where: { $0.outcome == .unreadable }) {
                session.attempt.state = .needsReview
                session.attempt.error = "Some text could not be read. Inspect the original or retry the unreadable regions."
            } else {
                session.completeResults = session.attempt.results
                session.attempt.state = .ready
                session.attempt.error = nil
            }
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

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
        return session.id
    }

    public func setActive(_ active: Bool) {}
    public func waitUntilIdle() async {}
}

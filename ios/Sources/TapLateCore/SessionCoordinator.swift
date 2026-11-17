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
}

@MainActor public protocol SessionRepository {
    func load() throws -> [ScreenshotSession]
    func insert(_ session: ScreenshotSession, image: Data) throws
}

@MainActor @Observable public final class SessionCoordinator {
    public private(set) var sessions: [ScreenshotSession]
    private let repository: any SessionRepository

    public init(repository: any SessionRepository) throws {
        self.repository = repository
        self.sessions = try repository.load()
    }

    @discardableResult public func capture(_ image: CapturedImage) throws -> UUID {
        guard !image.data.isEmpty, image.width > 0, image.height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let session = ScreenshotSession(id: UUID(), createdAt: Date(), width: image.width, height: image.height)
        try repository.insert(session, image: image.data)
        sessions.append(session)
        return session.id
    }
}

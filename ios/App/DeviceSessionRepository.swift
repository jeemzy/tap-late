import Foundation
import SwiftData
import TapLateCore

@Model final class SavedSession {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var payload: Data

    init(session: ScreenshotSession, payload: Data) {
        id = session.id
        createdAt = session.createdAt
        self.payload = payload
    }
}

@MainActor final class DeviceSessionRepository: SessionRepository {
    private let container: ModelContainer
    private let context: ModelContext
    let directory: URL

    init(directory: URL? = nil) throws {
        let base = directory ?? URL.applicationSupportDirectory.appendingPathComponent("TapLate", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var excluded = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        self.directory = base
        let schema = Schema([SavedSession.self])
        let configuration = ModelConfiguration(schema: schema, url: base.appendingPathComponent("Sessions.store"), cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func load() throws -> [ScreenshotSession] {
        let rows = try context.fetch(FetchDescriptor<SavedSession>(sortBy: [SortDescriptor(\.createdAt)]))
        return try rows.map { try JSONDecoder().decode(ScreenshotSession.self, from: $0.payload) }
    }

    func insert(_ session: ScreenshotSession, image: Data) throws {
        let payload = try JSONEncoder().encode(session)
        let url = imageURL(session.id)
        try image.write(to: url, options: [.atomic, .completeFileProtection])
        do {
            context.insert(SavedSession(session: session, payload: payload))
            try context.save()
        } catch {
            context.rollback()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func imageURL(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("png")
    }

    func update(_ session: ScreenshotSession) throws {
        let id = session.id
        let descriptor = FetchDescriptor<SavedSession>(predicate: #Predicate { $0.id == id })
        guard let saved = try context.fetch(descriptor).first else { throw CocoaError(.fileNoSuchFile) }
        let payload = try JSONEncoder().encode(session)
        saved.payload = payload
        do { try context.save() } catch { context.rollback(); throw error }
    }
}

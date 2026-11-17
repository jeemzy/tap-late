import Foundation
import Observation
import TapLateCore

@MainActor @Observable final class AppModel {
    static let shared = AppModel()
    private(set) var repository: DeviceSessionRepository?
    private(set) var coordinator: SessionCoordinator?
    var openSessionID: UUID?
    var error: String?

    private init() {
        do {
            let repository = try DeviceSessionRepository()
            self.repository = repository
            coordinator = try SessionCoordinator(repository: repository)
        } catch {
            self.error = "Screenshot storage could not open. Restart the app and try again."
        }
    }

    @discardableResult func importImage(_ data: Data) async throws -> UUID {
        guard let coordinator else { throw CocoaError(.fileWriteUnknown) }
        let image = try await ImageImport.normalize(data)
        let id = try coordinator.capture(image)
        openSessionID = id
        return id
    }
}

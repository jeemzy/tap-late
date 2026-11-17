import Foundation
import Observation
import TapLateCore
import UIKit

@MainActor @Observable final class AppModel {
    static let shared = AppModel()
    private(set) var repository: DeviceSessionRepository?
    private(set) var coordinator: SessionCoordinator?
    var openSessionID: UUID?
    var error: String?
    private(set) var isPreview = false

    private init() {
        do {
            #if DEBUG
            isPreview = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            let directory = isPreview ? URL.temporaryDirectory.appendingPathComponent("TapLate-Preview-" + UUID().uuidString) : nil
            #else
            let directory: URL? = nil
            #endif
            let repository = try DeviceSessionRepository(directory: directory)
            self.repository = repository
            #if DEBUG
            if isPreview { coordinator = try SessionCoordinator(repository: repository, engine: PreviewEngine()) }
            else { coordinator = try SessionCoordinator(repository: repository, engine: AppleFastEngine(repository: repository)) }
            #else
            coordinator = try SessionCoordinator(repository: repository, engine: AppleFastEngine(repository: repository))
            #endif
        } catch {
            self.error = "Screenshot storage could not open. Restart the app and try again."
        }
    }

    @discardableResult func importImage(_ data: Data, override: EngineConfiguration? = nil) async throws -> UUID {
        guard let coordinator else { throw CocoaError(.fileWriteUnknown) }
        let image = try await ImageImport.normalize(data)
        let id = try coordinator.capture(image, override: override)
        openSessionID = id
        return id
    }

    func languagesPrepared() {
        guard let coordinator else { return }
        do {
            for session in coordinator.sessions where session.attempt.state == .needsPreparation { try coordinator.retry(session.id) }
        } catch { self.error = error.localizedDescription }
    }

    func seedPreviewIfNeeded() {
        #if DEBUG
        guard isPreview, let coordinator, coordinator.sessions.isEmpty else { return }
        do {
            let image = PreviewEngine.image()
            openSessionID = try coordinator.capture(image)
        } catch { self.error = error.localizedDescription }
        #endif
    }
}

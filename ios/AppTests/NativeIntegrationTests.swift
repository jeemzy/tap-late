import Foundation
import Testing
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Translation
import TapLateCore
@testable import TapLate

@Suite @MainActor struct NativeIntegrationTests {
    @Test func `native import normalizes rotated images and rejects invalid input`() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let png = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 200), format: format).pngData { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        }
        let normalized = try await ImageImport.normalize(png)
        #expect(normalized.width == 100 && normalized.height == 200)
        #expect(UIImage(data: normalized.data)?.imageOrientation == .up)
        let encoded = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil))
        let cgImage = try #require(UIImage(data: png)?.cgImage)
        CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let rotated = try await ImageImport.normalize(encoded as Data)
        #expect(rotated.width == 200 && rotated.height == 100)
        #expect(UIImage(data: rotated.data)?.imageOrientation == .up)
        await #expect(throws: ImageImportError.self) { try await ImageImport.normalize(Data([0, 1, 2])) }
    }

    @Test func `saved capture survives a new native repository and is excluded from backup`() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try DeviceSessionRepository(directory: directory)
        let coordinator = try SessionCoordinator(repository: repository)
        let image = PreviewEngine.image()
        let id = try coordinator.capture(image)
        let restored = try SessionCoordinator(repository: DeviceSessionRepository(directory: directory))
        #expect(restored.sessions.map(\.id) == [id])
        #expect(try Data(contentsOf: repository.imageURL(id)) == image.data)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func applePreferenceChecksReadinessAndKeepsPriorResult() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try DeviceSessionRepository(directory: directory)
        let original = PreviewEngine.image()
        let capture = try SessionCoordinator(repository: repository)
        let id = try capture.capture(original)
        var saved = try #require(capture.sessions.first)
        let region = PreviewEngine.regions[0]
        saved.regions = [region]
        saved.recognized = true
        saved.completeResults = [region.id: RegionTranslation(source: region.rawText, translation: "Blue")]
        saved.attempt.state = .ready
        try repository.update(saved)
        var status = LanguageAvailability.Status.supported
        var requested: [ApplePreference] = []
        let engine = AppleTranslationEngine(repository: repository) { preference in
            requested.append(preference)
            return status
        }
        let store = try SessionCoordinator(repository: repository, engine: engine)
        try store.retry(id, configuration: .init(engine: .appleHighFidelity))
        store.setActive(true)
        await store.waitUntilIdle()
        #expect(store.sessions[0].attempt.state == .needsPreparation)
        status = .unsupported
        try store.retry(id)
        await store.waitUntilIdle()
        #expect(store.sessions[0].attempt.state == .failed)
        #expect(requested == [.highFidelity, .highFidelity])
        #expect(store.sessions[0].displayedResults[region.id]?.translation == "Blue")
        #expect(store.sessions[0].regions == [region])
        #expect(store.defaultConfiguration.engine == .appleFast)
    }

    @Test func missingImageDeletionAndOrphanRecovery() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try DeviceSessionRepository(directory: directory)
        let store = try SessionCoordinator(repository: repository)
        let id = try store.capture(PreviewEngine.image())
        try FileManager.default.removeItem(at: repository.imageURL(id))
        let orphan = repository.imageURL(UUID())
        try Data([0]).write(to: orphan)
        let restored = try SessionCoordinator(repository: DeviceSessionRepository(directory: directory))
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        try restored.deleteSession(id)
        #expect(try DeviceSessionRepository(directory: directory).load().isEmpty)
    }

    @Test func `native Vision recognizes Chinese text with independent valid regions`() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try DeviceSessionRepository(directory: directory)
        let coordinator = try SessionCoordinator(repository: repository)
        try coordinator.capture(PreviewEngine.image())
        let session = try #require(coordinator.sessions.first)
        let regions = try await AppleTranslationEngine(repository: repository).recognize(session)
        #expect(regions.filter { $0.rawText.range(of: "\\p{Han}", options: .regularExpression) != nil }.count >= 2)
        #expect(Set(regions.map(\.id)).count == regions.count)
        #expect(regions.allSatisfy { $0.rect.x >= 0 && $0.rect.y >= 0 && $0.rect.width > 0 && $0.rect.height > 0 })
    }
}

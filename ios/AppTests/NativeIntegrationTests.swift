import Foundation
import Testing
import UIKit
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

    @Test func `native Vision recognizes Chinese text with independent valid regions`() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try DeviceSessionRepository(directory: directory)
        let coordinator = try SessionCoordinator(repository: repository)
        try coordinator.capture(PreviewEngine.image())
        let session = try #require(coordinator.sessions.first)
        let regions = try await AppleFastEngine(repository: repository).recognize(session)
        #expect(regions.filter { $0.rawText.range(of: "\\p{Han}", options: .regularExpression) != nil }.count >= 2)
        #expect(Set(regions.map(\.id)).count == regions.count)
        #expect(regions.allSatisfy { $0.rect.x >= 0 && $0.rect.y >= 0 && $0.rect.width > 0 && $0.rect.height > 0 })
    }
}

import SwiftUI
import TapLateCore
import XCTest
@testable import TapLate

@MainActor final class WarmCaptureTests: XCTestCase {
    func testSecondImportReplacesVisibleScreenshot() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try DeviceSessionRepository(directory: directory)
        let model = try AppModel(repository: repository, engine: TwoCaptureEngine())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let previousWindow = scene.keyWindow
        window.rootViewController = UIHostingController(rootView: HomeView(model: model))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }

        let first = try await model.importImage(screenshot(.red))
        let firstCanvas = try await visibleCanvas(in: window, translation: "Red", session: first, repository: repository)
        firstCanvas.setZoomScale(firstCanvas.minimumZoomScale * 2, animated: false)
        let firstButton = try XCTUnwrap(descendant(OverlayButton.self, in: firstCanvas))
        firstButton.sendActions(for: .touchUpInside)

        let second = try await model.importImage(screenshot(.blue))
        let secondCanvas = try await visibleCanvas(in: window, translation: "Blue", session: second, repository: repository)
        XCTAssertFalse(firstCanvas === secondCanvas)
        XCTAssertEqual(secondCanvas.zoomScale, secondCanvas.minimumZoomScale, accuracy: 0.01)
        XCTAssertFalse(try XCTUnwrap(descendant(OverlayButton.self, in: secondCanvas)).isSelected)
        XCTAssertEqual(model.openSessionID, second)
        XCTAssertEqual(try repository.load().map(\.id), [first, second])
    }

    private func screenshot(_ color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 400, height: 800)
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func visibleCanvas(in window: UIWindow, translation: String, session: UUID,
                               repository: DeviceSessionRepository) async throws -> CanvasScrollView {
        let saved = try Data(contentsOf: repository.imageURL(session))
        let expected = try XCTUnwrap(UIImage(data: saved)?.pngData())
        let deadline = ContinuousClock.now + .seconds(8)
        repeat {
            window.layoutIfNeeded()
            if let canvas = descendant(CanvasScrollView.self, in: window),
               let original = descendant(UIImageView.self, in: canvas),
               original.image?.pngData() == expected,
               descendant(OverlayButton.self, in: canvas)?.overlay.attributedText?.string == translation {
                return canvas
            }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        throw NSError(domain: "WarmCaptureTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "The visible canvas never showed the saved image and its \(translation) overlay together."
        ])
    }

    private func descendant<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let found = view as? T { return found }
        for child in view.subviews where !child.isHidden {
            if let found = descendant(type, in: child) { return found }
        }
        return nil
    }
}

@MainActor private struct TwoCaptureEngine: ScreenshotEngine {
    func recognize(_ session: ScreenshotSession) async throws -> [TextRegion] {
        [TextRegion(id: "r1", rawText: session.attempt.order == 1 ? "红" : "蓝", confidence: 1,
                    rect: PixelRect(x: 30, y: 100, width: 200, height: 40),
                    appearance: TextAppearance(background: .init(red: 255, green: 255, blue: 255),
                                               foreground: .init(red: 0, green: 0, blue: 0)))]
    }

    func translate(_ regions: [TextRegion], configuration: EngineConfiguration,
                   emit: @MainActor (String, RegionTranslation) throws -> Void) async throws {
        for region in regions {
            try emit(region.id, RegionTranslation(source: region.rawText, translation: region.rawText == "红" ? "Red" : "Blue"))
        }
    }
}

import AppIntents
import UniformTypeIdentifiers

struct TranslateScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate Screenshot"
    static let description = IntentDescription("Open a screenshot in tap-late and translate it on your iPhone.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var image: IntentFile

    @MainActor func perform() async throws -> some IntentResult {
        try await AppModel.shared.importImage(image.data)
        return .result()
    }
}

struct TapLateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateScreenshotIntent(),
            phrases: ["Translate a screenshot with \(.applicationName)"],
            shortTitle: "Translate Screenshot",
            systemImageName: "translate"
        )
    }
}

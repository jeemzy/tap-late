import AppIntents
import UniformTypeIdentifiers
import TapLateCore

enum ShortcutEngine: String, AppEnum {
    case appleFast, appleHighFidelity
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Translation Engine"
    static let caseDisplayRepresentations: [ShortcutEngine: DisplayRepresentation] = [.appleFast: "Apple Fast", .appleHighFidelity: "Apple High Fidelity"]
}

struct TranslateScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate Screenshot"
    static let description = IntentDescription("Open a screenshot in tap-late and translate it on your iPhone.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var image: IntentFile

    @Parameter(title: "Engine") var engine: ShortcutEngine?

    @MainActor func perform() async throws -> some IntentResult {
        let override: EngineConfiguration? = engine.map { EngineConfiguration(engine: $0 == .appleFast ? .appleFast : .appleHighFidelity) }
        try await AppModel.shared.importImage(image.data, override: override)
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

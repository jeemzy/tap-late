import SwiftUI
import Translation
import Security

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: TranslationSession.Configuration?
    @State private var preparing = false
    @State private var message: String?
    @State private var secureStorage = "Checking…"
    var onPrepared: @MainActor @Sendable () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Translation") {
                    LabeledContent("Language", value: "Chinese → English")
                    LabeledContent("Default engine", value: "Apple Fast")
                    Text("Translates on your iPhone. Your screenshots stay on this device.")
                        .foregroundStyle(.secondary)
                    Button(preparing ? "Preparing languages…" : "Prepare offline translation") {
                        preparing = true
                        message = nil
                        if configuration != nil { configuration?.invalidate() }
                        else {
                            configuration = .init(source: Locale.Language(identifier: "zh-Hans"), target: Locale.Language(identifier: "en"), preferredStrategy: .lowLatency)
                        }
                    }
                    .disabled(preparing)
                    if let message { Text(message).foregroundStyle(.secondary) }
                }
                Section("This installation") {
                    LabeledContent("Secure storage", value: secureStorage)
                    Text("Keep the same signing identity when updating through iloader so saved screenshots and secure settings remain available.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { secureStorage = InstallationKeychain.check() ? "Available" : "Unavailable — try unlocking your iPhone" }
            .translationTask(configuration) { @Sendable session in
                let result: String
                let succeeded: Bool
                do {
                    try await session.prepareTranslation()
                    result = "Chinese and English are ready for offline translation."
                    succeeded = true
                } catch {
                    result = "Languages could not be prepared. Check your connection and try again.\n" + error.localizedDescription
                    succeeded = false
                }
                await MainActor.run {
                    message = result
                    preparing = false
                    if succeeded { onPrepared() }
                }
            }
        }
    }
}

private enum InstallationKeychain {
    static func check() -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "taplate.installation-check",
                                    kSecAttrAccount as String: "local"]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = Data(UUID().uuidString.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

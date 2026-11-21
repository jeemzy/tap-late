import SwiftUI
import Translation
import Security

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: TranslationSession.Configuration?
    @State private var preparing = false
    @State private var message: String?
    @State private var secureStorage = "Checking…"
    let model: AppModel
    let sessionPreference: ApplePreference?
    @State private var readiness: String?
    private var preference: ApplePreference { sessionPreference ?? model.defaultPreference }

    init(model: AppModel, sessionPreference: ApplePreference? = nil) {
        self.model = model
        self.sessionPreference = sessionPreference
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Translation") {
                    LabeledContent("Language", value: "Chinese → English")
                    if sessionPreference != nil {
                        LabeledContent("Requested strategy", value: preference.rawValue)
                    } else {
                        Picker("Future captures", selection: Binding(get: { model.defaultPreference }, set: { model.defaultPreference = $0; message = nil; configuration = nil })) {
                            ForEach(ApplePreference.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.disabled(preparing)
                    }
                    Text(preference == .fast ? "Prefers faster on-device translation." : "Prefers Apple Intelligence on this iPhone. Apple may use another on-device strategy depending on device and language readiness.")
                        .foregroundStyle(.secondary)
                    if let readiness { Text(readiness).font(.footnote) }
                    Button(preparing ? "Preparing languages…" : "Prepare offline translation") {
                        preparing = true
                        message = nil
                        if configuration != nil { configuration?.invalidate() }
                        else {
                            configuration = .init(source: ApplePreference.source, target: ApplePreference.target, preferredStrategy: preference.strategy)
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
            .task { secureStorage = InstallationKeychain.check() }
            .task(id: preference) {
                let selected = preference
                let status = await selected.readiness()
                guard !Task.isCancelled else { return }
                switch status {
                case .installed: readiness = "Chinese and English are ready offline."
                case .supported: readiness = "Prepare the languages while connected."
                case .unsupported: readiness = "Unavailable for this language pair. Choose another strategy."
                @unknown default: readiness = "Readiness could not be determined."
                }
            }
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
                    if succeeded { readiness = result; model.languagesPrepared(for: preference) }
                }
            }
        }
    }
}

@MainActor private enum InstallationKeychain {
    static func check() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "taplate.installation-check",
                                    kSecAttrAccount as String: "local"]
        let preference = "taplate.installation-check.expected"
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &found)
        let expected = UserDefaults.standard.data(forKey: preference)
        if status == errSecSuccess, let stored = found as? Data {
            if let expected, stored != expected { return "Changed since the previous installation" }
            UserDefaults.standard.set(stored, forKey: preference)
            return "Available"
        }
        guard status == errSecItemNotFound else { return "Unavailable — try unlocking your iPhone" }
        guard expected == nil else { return "Previous secure storage is unavailable — check the signing identity" }
        var item = query
        let marker = Data(UUID().uuidString.utf8)
        item[kSecValueData as String] = marker
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess,
              SecItemCopyMatching(lookup as CFDictionary, &found) == errSecSuccess,
              found as? Data == marker else { return "Unavailable — try unlocking your iPhone" }
        UserDefaults.standard.set(marker, forKey: preference)
        return "Available"
    }
}

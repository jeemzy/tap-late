import SwiftUI
import PhotosUI
import TapLateCore

@main struct TapLateApp: App {
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
                .preferredColorScheme(model.isPreview && ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : nil)
        }
    }
}

struct HomeView: View {
    @Bindable var model: AppModel
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var settingsPresented = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Choose a screenshot", systemImage: "photo")
                    }
                    .disabled(importing || model.coordinator == nil)
                    if let latest = model.coordinator?.sessions.last {
                        Button { model.openSessionID = latest.id } label: {
                            Label("Open last screenshot", systemImage: "rectangle.on.rectangle")
                        }
                        .accessibilityIdentifier("open-last-screenshot")
                    }
                } header: {
                    Text("Chinese → English")
                } footer: {
                    Text(importing ? "Opening screenshot…" : "Use Back Tap for a new capture, or choose one saved in Photos.")
                }
                if let coordinator = model.coordinator {
                    let pending = coordinator.sessions.filter { $0.attempt.state != .ready }
                    if !pending.isEmpty {
                        Section("Queue") {
                            ForEach(pending) { session in
                                Button { model.openSessionID = session.id } label: {
                                    VStack(alignment: .leading) {
                                        Text(session.createdAt, style: .time)
                                        Text(session.attempt.state.displayName).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if let error = coordinator.storageError { Section { Text(error).foregroundStyle(.red) } }
                }
                Section("Back Tap") {
                    Text("In Shortcuts, add Take Screenshot, then tap-late’s Translate Screenshot action. Pass the screenshot into the action.")
                    Text("Assign that Shortcut in Settings → Accessibility → Touch → Back Tap.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("tap-late")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { settingsPresented = true }
                }
            }
            .sheet(isPresented: $settingsPresented) { SettingsView(onPrepared: model.languagesPrepared) }
            .navigationDestination(isPresented: Binding(
                get: { model.openSessionID != nil },
                set: { if !$0 { model.openSessionID = nil } }
            )) {
                if let id = model.openSessionID {
                    ScreenshotViewer(model: model, sessionID: id).id(id)
                }
            }
        }
        .task {
            model.coordinator?.setActive(scenePhase == .active)
            model.seedPreviewIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in model.coordinator?.setActive(phase == .active) }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            importing = true
            Task {
                defer { importing = false; photo = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw ImageImportError.invalid }
                    try await model.importImage(data)
                } catch { model.error = error.localizedDescription }
            }
        }
        .alert("Could not open screenshot", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "Try again.") }
    }
}

import AVKit
import SwiftUI
import TapLateCore

struct LiveTranslationView: View {
    let model: AppModel
    @State private var live = LiveTranslation()
    @AppStorage("taplate.live.scope") private var scope = LiveReadingScope.zone
    @AppStorage("taplate.live.zone") private var zone = ReadingZone.middle
    @AppStorage("taplate.live.engine") private var engine = ApplePreference.fast
    @State private var showLanguages = false

    var body: some View {
        Form {
            Section("Reading scope") {
                ForEach(LiveReadingScope.allCases, id: \.self) { option in
                    Button {
                        scope = option
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.rawValue).foregroundStyle(.primary)
                                Text(option == .zone ? "Magnify the part of the screen you choose." : "Show the translated page in the window.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: scope == option ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(scope == option ? Color.green : Color.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(option == .zone ? "live-zone" : "live-whole")
                    .accessibilityAddTraits(scope == option ? .isSelected : [])
                }
                if scope == .zone {
                    Picker("Reading zone", selection: $zone) {
                        ForEach(ReadingZone.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
            }.disabled(live.phase != .idle)
            Section("Chinese → English") {
                Picker("Engine", selection: $engine) {
                    ForEach(ApplePreference.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("live-engine")
                Button("Prepare offline languages") { showLanguages = true }
            }.disabled(live.phase != .idle)
            Section {
                #if DEBUG && targetEnvironment(simulator)
                Text("Simulator sample pages").font(.headline)
                if live.framesPresented > 0 {
                    Text("\(live.sampleDescription) · \(live.framesPresented) frames enqueued")
                        .accessibilityIdentifier("live-sample-status")
                }
                #endif
                if live.phase == .idle {
                    Button("Start Live Translation") {
                        Task { await live.start(scope: scope, zone: zone, engine: engine) }
                    }.accessibilityIdentifier("start-live")
                } else {
                    LivePreview(display: live.display)
                        .frame(height: 100)
                        .accessibilityHidden(true)
                    Text(status).accessibilityAddTraits(.updatesFrequently)
                    Button("Stop Live Translation", role: .destructive) { live.stop() }
                        .accessibilityIdentifier("stop-live")
                        .disabled(live.phase == .stopping)
                }
                if let message = live.message { Text(message).foregroundStyle(.secondary) }
            } footer: {
                Text("Share your screen, then open JD. Close the floating window to stop. Live frames stay on this iPhone and aren’t saved to history.")
            }
        }
        .navigationTitle("Live Translation")
        .navigationBarBackButtonHidden(live.phase != .idle)
        .sheet(isPresented: $showLanguages) { SettingsView(model: model, sessionPreference: engine) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in live.stop() }
        .onDisappear { if live.phase != .idle && UIApplication.shared.applicationState == .active { live.stop() } }
    }

    private var status: String {
        switch live.phase {
        case .checking: "Checking offline languages…"
        case .picker: "Choose your screen in the sharing picker."
        case .starting: "Opening the floating window…"
        case .live: "Live translation is on. Open JD and scroll."
        case .stopping: "Stopping…"
        case .idle: ""
        }
    }
}

private struct LivePreview: UIViewRepresentable {
    let display: AVSampleBufferDisplayLayer
    func makeUIView(context: Context) -> Surface { Surface(display) }
    func updateUIView(_ view: Surface, context: Context) {}

    final class Surface: UIView {
        private let display: AVSampleBufferDisplayLayer
        init(_ display: AVSampleBufferDisplayLayer) {
            self.display = display
            super.init(frame: .zero)
            backgroundColor = .black
            layer.addSublayer(display)
        }
        required init?(coder: NSCoder) { nil }
        override func layoutSubviews() {
            super.layoutSubviews()
            display.frame = bounds
        }
    }
}

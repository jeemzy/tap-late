import SwiftUI
import TapLateCore

extension ProcessingState {
    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .recognizing: "Reading screenshot…"
        case .translating: "Translating…"
        case .needsPreparation: "Offline languages needed"
        case .needsReview: "Some text needs review"
        case .failed: "Translation needs attention"
        case .ready: "Ready"
        }
    }
}

struct ScreenshotViewer: View {
    let model: AppModel
    let sessionID: UUID
    @State private var image: UIImage?
    @State private var loading = true
    @State private var translated = true
    @State private var selectedID: String?
    @State private var islandHeight: CGFloat = 0
    @State private var statusHeight: CGFloat = 0
    @State private var settings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var session: ScreenshotSession? { model.coordinator?.sessions.first { $0.id == sessionID } }
    private var selected: TextRegion? { session?.regions.first { $0.id == selectedID } }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                if let image, let session {
                    ScreenshotCanvas(image: image, regions: session.regions, results: session.displayedResults,
                                     translated: translated, selectedID: selectedID, coveredHeight: islandHeight,
                                     coveredTopHeight: statusHeight,
                                     onSelect: { selectedID = $0 })
                        .ignoresSafeArea()
                } else if loading {
                    ProgressView("Opening screenshot…")
                } else {
                    ContentUnavailableView("Screenshot unavailable", systemImage: "photo", description: Text("Return and choose the screenshot again."))
                }
            }
            .overlay(alignment: .top) {
                if let session, session.attempt.state != .ready || session.regions.isEmpty {
                    VStack(spacing: 8) {
                        if model.isPreview { Text("UI preview fixture").font(.caption).foregroundStyle(.secondary) }
                        Text(session.regions.isEmpty && session.attempt.state == .ready ? "No text was found in this screenshot." : session.attempt.state.displayName)
                            .font(.subheadline.weight(.medium))
                        if let error = session.attempt.error {
                            Text(error).font(.caption).multilineTextAlignment(.center)
                        }
                        if session.attempt.state == .needsPreparation {
                            Button("Prepare languages") { settings = true }.buttonStyle(.glassProminent)
                        } else if session.attempt.state == .failed || session.attempt.state == .needsReview {
                            Button(session.attempt.state == .needsReview ? "Retry unreadable regions" : "Retry unfinished regions") { retry() }.buttonStyle(.glass)
                        }
                    }
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .padding(.horizontal, 12).padding(.top, 8)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { statusHeight = $0 }
                }
            }
            .overlay(alignment: .bottom) {
                if let selected, let session {
                    DetailsIsland(region: selected, result: session.displayedResults[selected.id],
                                  maximumHeight: max(140, geometry.size.height * 0.36), onClose: { selectedID = nil })
                        .padding(.horizontal, 6).padding(.bottom, 6)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { islandHeight = $0 }
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.22), value: selectedID)
        }
        .navigationTitle(model.isPreview ? "UI preview · Chinese → English" : "Chinese → English")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(translated ? "Show original" : "Show translations", systemImage: translated ? "square.2.layers.3d" : "square.2.layers.3d.top.filled") {
                    translated.toggle()
                }
                .accessibilityIdentifier("toggle-original")
                Menu {
                    Button("Translate again", systemImage: "arrow.clockwise") { retry() }
                        .disabled(session?.attempt.state == .queued || session?.attempt.state == .recognizing || session?.attempt.state == .translating)
                    Button("Translation settings", systemImage: "gearshape") { settings = true }
                } label: { Label("More", systemImage: "ellipsis") }
            }
        }
        .sheet(isPresented: $settings) { SettingsView(onPrepared: model.languagesPrepared) }
        .onChange(of: selectedID) { _, id in if id == nil { islandHeight = 0 } }
        .onChange(of: session?.attempt.state) { _, state in
            if state == .ready, session?.regions.isEmpty == false { statusHeight = 0 }
        }
        .task(id: sessionID) {
            loading = true
            defer { loading = false }
            if let url = model.repository?.imageURL(sessionID), let data = try? Data(contentsOf: url) { image = UIImage(data: data) }
        }
    }

    private func retry() {
        do { try model.coordinator?.retry(sessionID) }
        catch { model.error = error.localizedDescription }
    }
}

private struct DetailsIsland: View {
    let region: TextRegion
    let result: RegionTranslation?
    let maximumHeight: CGFloat
    var onClose: () -> Void
    @State private var contentHeight: CGFloat = 180
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Original").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Close details", systemImage: "xmark", action: onClose)
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("close-details")
                }
                Text(result?.source ?? region.rawText).textSelection(.enabled)
                Text("Translation").font(.caption).foregroundStyle(.secondary)
                Text(result?.outcome == .unreadable ? "Unreadable — inspect the original or retry this region." : (result?.translation ?? "Not translated yet")).textSelection(.enabled)
                    .accessibilityIdentifier("detail-translation")
                HStack {
                    Button("Copy original", systemImage: "doc.on.doc") { UIPasteboard.general.string = result?.source ?? region.rawText }.frame(minHeight: 44)
                    Spacer()
                    if let translation = result?.translation {
                        Button("Copy translation", systemImage: "doc.on.doc") { UIPasteboard.general.string = translation }.frame(minHeight: 44)
                    }
                }.font(.caption).buttonStyle(.borderless)
            }
            .padding(16)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .frame(height: min(maximumHeight, contentHeight))
        .frame(maxWidth: 520)
        .background(reduceTransparency || contrast == .increased ? Color(uiColor: .secondarySystemBackground) : .clear, in: .rect(cornerRadius: 32))
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .accessibilityIdentifier("details-island")
    }
}

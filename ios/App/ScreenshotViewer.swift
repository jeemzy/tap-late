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
    @State private var preparationPreference: ApplePreference?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var session: ScreenshotSession? { model.coordinator?.sessions.first { $0.id == sessionID } }
    private var selected: TextRegion? { session?.regions.first { $0.id == selectedID } }
    private var showsStatus: Bool {
        guard let session else { return false }
        return session.attempt.state != .ready || session.regions.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                if let image, let session {
                    ScreenshotCanvas(image: image, regions: session.regions, results: session.displayedResults,
                                     translated: translated, selectedID: selectedID, coveredHeight: islandHeight,
                                     coveredTopHeight: showsStatus ? statusHeight : 0,
                                     onSelect: { selectedID = $0 })
                        .ignoresSafeArea()
                } else if loading {
                    ProgressView("Opening screenshot…")
                } else {
                    ContentUnavailableView("Screenshot unavailable", systemImage: "photo", description: Text("Return and choose the screenshot again."))
                }
            }
            .overlay(alignment: .top) {
                if let session, showsStatus {
                    VStack(spacing: 8) {
                        if model.isPreview { Text("UI preview fixture").font(.caption).foregroundStyle(.secondary) }
                        Text(session.regions.isEmpty && session.attempt.state == .ready ? "No text was found in this screenshot." : session.attempt.state.displayName)
                            .font(.subheadline.weight(.medium))
                        if let error = session.attempt.error {
                            Text(error).font(.caption).multilineTextAlignment(.center)
                        }
                        if session.attempt.state == .needsPreparation {
                            Button("Prepare languages") { preparationPreference = ApplePreference(engine: session.attempt.configuration.engine); settings = true }.buttonStyle(.glassProminent)
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
                    DetailsIsland(model: model, session: session, region: selected, result: session.displayedResults[selected.id],
                                  maximumHeight: max(140, geometry.size.height * 0.36), onClose: { selectedID = nil })
                        .id(selected.id)
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
                    #if DEBUG
                    if model.isPreview && ProcessInfo.processInfo.arguments.contains("--warm-capture") {
                        Button("Submit second screenshot") {
                            Task {
                                do { try await PreviewEngine.submitSecondCapture() }
                                catch { model.error = error.localizedDescription }
                            }
                        }
                    }
                    #endif
                    Section {
                        Menu("Translate again", systemImage: "arrow.clockwise") {
                            ForEach(ApplePreference.allCases, id: \.self) { preference in
                                Button(preference.rawValue) {
                                    do { try model.coordinator?.retry(sessionID, configuration: .init(engine: preference.engine)) }
                                    catch { model.error = error.localizedDescription }
                                }
                            }
                        }
                            .disabled(session?.attempt.state == .queued || session?.attempt.state == .recognizing || session?.attempt.state == .translating)
                    } header: {
                        if let session, let preference = ApplePreference(engine: session.attempt.configuration.engine) {
                            Text("Requested: \(preference.rawValue)")
                        }
                    }
                    Button("Translation settings", systemImage: "gearshape") { preparationPreference = nil; settings = true }
                } label: { Label("More", systemImage: "ellipsis") }
                .accessibilityValue(session.flatMap { ApplePreference(engine: $0.attempt.configuration.engine)?.rawValue } ?? "")
            }
        }
        .sheet(isPresented: $settings) { SettingsView(model: model, sessionPreference: preparationPreference) }
        .onChange(of: selectedID) { _, id in if id == nil { islandHeight = 0 } }
        .onChange(of: showsStatus) { _, visible in
            if !visible { statusHeight = 0 }
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
    let model: AppModel
    let session: ScreenshotSession
    let region: TextRegion
    let result: RegionTranslation?
    let maximumHeight: CGFloat
    var onClose: () -> Void
    @State private var contentHeight: CGFloat = 180
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var translationText: String {
        result?.outcome == .unreadable ? "Unreadable — inspect the original or retry this region." : (result?.translation ?? "Not translated yet")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let source = session.source(for: region)
                let amounts = PriceAmount.candidates(in: source)
                if !amounts.isEmpty, let coordinator = model.coordinator, let rates = model.rates {
                    CurrencyDetails(amounts: amounts, choices: session.currencyChoices[region.id]?.currencies ?? [:],
                                    rates: rates, source: source, translation: translationText,
                                    canCopyTranslation: result?.translation != nil, onClose: onClose) { amount, currency in
                        try coordinator.chooseCurrency(currency, sessionID: session.id, regionID: region.id, source: source, amountID: amount.id)
                    }
                    .id(source)
                } else {
                    HStack {
                        Text("Original").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Close details", systemImage: "xmark", action: onClose)
                            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("close-details")
                    }
                    Text(source).textSelection(.enabled)
                    Text("Translation").font(.caption).foregroundStyle(.secondary)
                    Text(translationText).textSelection(.enabled)
                        .accessibilityIdentifier("detail-translation")
                    HStack {
                        Button("Copy original", systemImage: "doc.on.doc") { UIPasteboard.general.string = source }.frame(minHeight: 44)
                        Spacer()
                        if let translation = result?.translation {
                            Button("Copy translation", systemImage: "doc.on.doc") { UIPasteboard.general.string = translation }.frame(minHeight: 44)
                        }
                    }.font(.caption).buttonStyle(.borderless)
                }
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

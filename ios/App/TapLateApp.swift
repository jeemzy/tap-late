import SwiftUI
import PhotosUI
import TapLateCore

@main struct TapLateApp: App {
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup { HomeView(model: model) }
    }
}

struct HomeView: View {
    @Bindable var model: AppModel
    @State private var path: [UUID] = []
    @State private var photo: PhotosPickerItem?
    @State private var importing = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(importing ? "Opening screenshot…" : "Choose a screenshot", systemImage: "photo")
                    }
                    .disabled(importing || model.coordinator == nil)
                    if let latest = model.coordinator?.sessions.last {
                        NavigationLink(value: latest.id) {
                            Label("Open last screenshot", systemImage: "rectangle.on.rectangle")
                        }
                    }
                } header: {
                    Text("Chinese → English")
                } footer: {
                    Text("Use Back Tap for a new capture, or choose one saved in Photos.")
                }
                Section("Back Tap") {
                    Text("In Shortcuts, add Take Screenshot, then tap-late’s Translate Screenshot action. Pass the screenshot into the action.")
                    Text("Assign that Shortcut in Settings → Accessibility → Touch → Back Tap.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("tap-late")
            .navigationDestination(for: UUID.self) { id in
                OriginalViewer(model: model, sessionID: id)
            }
            .onChange(of: model.openSessionID) { _, id in
                if let id { path = [id] }
            }
            .task {
                if let id = model.openSessionID { path = [id] }
            }
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
}

struct OriginalViewer: View {
    let model: AppModel
    let sessionID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            if let image {
                ZoomableScreenshot(image: image).ignoresSafeArea()
            } else {
                ContentUnavailableView("Screenshot unavailable", systemImage: "photo", description: Text("Return and choose the screenshot again."))
            }
            HStack {
                Button("Back", systemImage: "chevron.left") { dismiss() }.labelStyle(.iconOnly)
                Text("Original").font(.headline)
                Spacer()
                Image(systemName: "translate").foregroundStyle(.secondary)
            }
            .padding(14)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let url = model.repository?.imageURL(sessionID), let data = try? Data(contentsOf: url) {
                image = UIImage(data: data)
            }
        }
    }
}

struct ZoomableScreenshot: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.maximumZoomScale = 8
        let imageView = UIImageView(image: image)
        imageView.frame = CGRect(origin: .zero, size: image.size)
        imageView.contentMode = .scaleAspectFit
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        guard scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
        let scale = min(scroll.bounds.width / image.size.width, scroll.bounds.height / image.size.height)
        scroll.minimumZoomScale = scale
        if context.coordinator.viewport != scroll.bounds.size {
            context.coordinator.viewport = scroll.bounds.size
            scroll.zoomScale = scale
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        var viewport: CGSize = .zero
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.contentInset = UIEdgeInsets(
                top: max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2), left: max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2), bottom: 0, right: 0
            )
        }
    }
}

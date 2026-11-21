import SwiftUI
import ImageIO
import TapLateCore

struct SessionHistory: View {
    let model: AppModel
    let coordinator: SessionCoordinator
    @State private var deletingGroup: UUID?

    var body: some View {
        if coordinator.groups.isEmpty {
            Section("History") {
                Text("No recent screenshots").foregroundStyle(.secondary)
            }
        }
        ForEach(coordinator.groups) { group in
            Section {
                ForEach(group.sessions) { session in
                    Button { model.openSessionID = session.id } label: {
                        HStack {
                            HistoryThumbnail(url: model.repository?.imageURL(session.id))
                            VStack(alignment: .leading) {
                                Text(session.createdAt, format: .dateTime.hour().minute().second())
                                Text(session.attempt.state.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("history-session")
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            do { try coordinator.deleteSession(session.id) } catch { model.error = error.localizedDescription }
                        }
                    }
                }
            } header: {
                HStack {
                    Text(group.newest, format: .dateTime.month(.abbreviated).day().hour().minute())
                    Spacer()
                    Button("Delete group", systemImage: "trash") { deletingGroup = group.id }
                        .labelStyle(.iconOnly)
                        .confirmationDialog("Delete all screenshots in this group?", isPresented: Binding(
                            get: { deletingGroup == group.id }, set: { if !$0 { deletingGroup = nil } }
                        )) {
                            Button("Delete screenshots", role: .destructive) {
                                do { try coordinator.deleteGroup(group.id) } catch { model.error = error.localizedDescription }
                            }
                        }
                }
            }
        }
    }
}

private struct HistoryThumbnail: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .frame(width: 40, height: 48)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
        .task(id: url) {
            if let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                   kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceCreateThumbnailWithTransform: true,
                   kCGImageSourceThumbnailMaxPixelSize: 144
               ] as CFDictionary) { image = UIImage(cgImage: thumbnail) }
            else { image = nil }
        }
    }
}

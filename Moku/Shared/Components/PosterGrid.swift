import SwiftUI

/// Cover grid for source titles, marking ones already in the library.
struct PosterGrid: View {
    let entries: [MediaEntry]
    let identifier: String
    let open: (MediaEntry) -> Void
    /// Called when the last poster appears, to load the next page.
    var reachEnd: (() async -> Void)?
    @Environment(LibraryStore.self) private var library
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(entries) { entry in
                Button {
                    open(entry)
                } label: {
                    card(entry)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(identifier).\(entry.id)")
                .contextMenu {
                    Button("Open", systemImage: "book") { open(entry) }
                    Button("Copy Title", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = entry.title
                    }
                }
            }
        }
        .task(id: entries.prefix(12).map(\.id)) {
            await CoverImagePipeline.shared.prefetch(entries.prefix(12).compactMap(\.coverURL))
        }
    }

    private func card(_ entry: MediaEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    CoverImage(url: entry.coverURL, symbol: entry.media.symbol).scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .overlay(alignment: .topLeading) {
                    if library.contains(entry) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NavigationStyle.background)
                            .padding(6)
                            .background(NavigationStyle.accent, in: Circle())
                            .padding(6)
                            .accessibilityLabel("Saved")
                    }
                }
                .padding(.bottom, 4)
            Text(entry.title).font(.subheadline.weight(.medium))
                .lineLimit(2).foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Text(entry.sourceName).font(.caption).lineLimit(1).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

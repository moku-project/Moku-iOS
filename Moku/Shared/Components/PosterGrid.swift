import SwiftUI

/// Cover grid for source titles, marking ones already in the library.
struct PosterGrid: View {
    let entries: [MediaEntry]
    let identifier: String
    let open: (MediaEntry) -> Void
    @Environment(LibraryStore.self) private var library
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(entries) { entry in
                Button { open(entry) } label: { card(entry) }
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
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { CoverImage(url: entry.coverURL, symbol: entry.media.symbol).scaledToFill() }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if library.contains(entry) {
                        Text("Saved").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(NavigationStyle.accent, in: Capsule())
                            .foregroundStyle(NavigationStyle.background)
                            .padding(6)
                    }
                }
            Text(entry.title).font(.caption).lineLimit(2, reservesSpace: true).foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Text(entry.sourceName).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

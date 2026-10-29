import SwiftUI

/// Desktop SeriesLinkPanel: mark library titles as the same series (for
/// example one manga on two sources). Linked titles share covers in the cover
/// picker. Stored on this device only, like desktop.
struct SeriesLinkSheet: View {
    let entry: MediaEntry
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var linked: [MediaEntry] { library.linkedEntries(for: entry.id) }
    private var candidates: [MediaEntry] {
        library.entries.filter { $0.id != entry.id && !linked.contains($0) }
    }
    private var results: [MediaEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return Array(candidates.filter { $0.title.localizedCaseInsensitiveContains(text) }.prefix(30))
    }
    /// Word overlap of at least 0.65, best eight, as on desktop.
    private var suggestions: [(MediaEntry, Double)] {
        Array(candidates.map { ($0, MigrateSheet.score($0.title, entry.title)) }
            .filter { $0.1 >= 0.65 }.sorted { $0.1 > $1.1 }.prefix(8))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Linked titles share covers and are treated as one series. Tap a linked title to unlink it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !linked.isEmpty {
                    Section("Linked") {
                        ForEach(linked) { item in
                            row(item, trailing: "CheckCircle.fill") {
                                Task { await library.setLinked(entry.id, item.id, linked: false) }
                            }
                            .accessibilityHint("Unlinks this title")
                        }
                    }
                }
                if !query.isEmpty {
                    Section("Results") {
                        if results.isEmpty { Text("No titles match.").foregroundStyle(.secondary) }
                        ForEach(results) { item in
                            row(item, trailing: "Plus") { link(item) }
                        }
                    }
                } else {
                    Section("Suggested") {
                        if suggestions.isEmpty {
                            Text("No suggestions. Search your library above.").foregroundStyle(.secondary)
                        }
                        ForEach(suggestions, id: \.0.id) { item, score in
                            row(item, detail: "\(Int(score * 100))% similar", trailing: "Plus") { link(item) }
                        }
                    }
                }
            }
            .textCase(nil)
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your library")
            .navigationTitle("Link as same series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                await library.load()
                await library.loadOrganization()
            }
        }
    }

    private func link(_ item: MediaEntry) {
        Task {
            await library.setLinked(entry.id, item.id, linked: true)
            query = ""
            Toaster.shared.show("Series linked", detail: item.title)
        }
    }

    private func row(_ item: MediaEntry, detail: String? = nil, trailing: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CoverImage(url: item.coverURL, symbol: item.media.symbol)
                    .frame(width: 36, height: 52).clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.subheadline).lineLimit(2)
                    Text([item.sourceName, detail].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                PhosphorIcon(trailing).foregroundStyle(NavigationStyle.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

/// Desktop CoverPickerPanel: choose this title's cover from its own source,
/// linked or similarly named library titles, or its AniList match.
struct CoverPickerSheet: View {
    let entry: MediaEntry
    let sourceCover: String?
    var changed: () -> Void = {}
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [Candidate] = []
    @State private var selected: Candidate.ID?
    @State private var working = false
    @State private var error: String?

    struct Candidate: Identifiable, Equatable {
        /// nil resets to the source's own cover.
        let url: String?
        let preview: URL?
        var label: String
        var id: String { url ?? "source" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TabView(selection: $selected) {
                    ForEach(candidates) { candidate in
                        VStack(spacing: 12) {
                            CoverImage(url: candidate.preview, contentMode: .fit, symbol: entry.media.symbol)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .frame(maxHeight: 360)
                            Text(candidate.label).font(.subheadline).foregroundStyle(GeneralStyle.label)
                        }
                        .padding(.horizontal, 40)
                        .tag(Optional(candidate.id))
                        .accessibilityElement(children: .combine)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: candidates.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                if candidates.count <= 1 {
                    Text("No other covers found. Link this title to the same series on another source, or match it to AniList, for more choices.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
                Button {
                    Task { await refetch() }
                } label: {
                    Text("Re-download from source").font(.subheadline)
                }
                .disabled(working)
                .accessibilityHint("Use this if the cover looks corrupted or wrong")
            }
            .padding(.vertical, 20)
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle("Cover image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use cover") { Task { await apply() } }
                        .disabled(working || selected == nil)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        await library.loadOrganization()
        var list = [Candidate(url: nil, preview: BackendAPI.coverURL(sourceCover), label: "This source")]
        let linked = library.linkedEntries(for: entry.id)
        let similar = library.entries.filter {
            $0.id != entry.id && $0.media == entry.media && !linked.contains($0)
                && MigrateSheet.score($0.title, entry.title) >= 0.65
        }
        for item in linked + similar {
            guard let preview = item.coverURL, let original = Self.original(preview) else { continue }
            list.append(Candidate(url: original, preview: preview, label: item.sourceName))
        }
        struct Response: Decodable, Sendable {
            struct Media: Decodable, Sendable {
                struct Metadata: Decodable, Sendable { let coverUrl: String? }
                let metadata: Metadata?
            }
            let media: Media?
        }
        if let response: Response = try? await BackendAPI.shared.graphql(
            "{ media(id: \(BackendAPI.literal(entry.id))) { metadata { coverUrl } } }", requiresSourceRuntime: false),
           let cover = response.media?.metadata?.coverUrl {
            list.append(Candidate(url: cover, preview: BackendAPI.coverURL(cover), label: "AniList"))
        }
        // Same image from several places: keep one, with every label.
        var unique: [Candidate] = []
        for candidate in list {
            let key = candidate.url.map(Self.stripQuery)
            if let index = unique.firstIndex(where: { $0.url.map(Self.stripQuery) == key && key != nil }) {
                unique[index].label += " · \(candidate.label)"
            } else {
                unique.append(candidate)
            }
        }
        candidates = unique
        selected = unique.first?.id
    }

    private func apply() async {
        guard let candidate = candidates.first(where: { $0.id == selected }) else { return }
        working = true
        defer { working = false }
        let url = candidate.url.map(BackendAPI.literal) ?? "null"
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                "mutation { setMediaCover(mediaId: \(BackendAPI.literal(entry.id)), url: \(url)) { id } }")
            await BackendAPI.shared.clearCoverCache()
            changed()
            Toaster.shared.show("Cover updated")
            dismiss()
        } catch {
            self.error = "Couldn’t change the cover. Try again."
        }
    }

    private func refetch() async {
        working = true
        defer { working = false }
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                "mutation { refetchMediaCover(mediaId: \(BackendAPI.literal(entry.id))) { id } }")
            await BackendAPI.shared.clearCoverCache()
            changed()
            Toaster.shared.show("Cover refetched from source")
            dismiss()
        } catch {
            self.error = "Couldn’t refetch the cover. Try again."
        }
    }

    /// Library covers are proxied as `/proxy/img/<base64url of the original>`.
    static func original(_ url: URL) -> String? {
        if url.scheme == "http" || url.scheme == "https" { return url.absoluteString }
        let prefix = "/proxy/img/"
        guard url.path.hasPrefix(prefix) else { return nil }
        var encoded = String(url.path.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded += "=" }
        return Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func stripQuery(_ value: String) -> String {
        value.split(separator: "?", maxSplits: 1).first.map(String.init) ?? value
    }
}

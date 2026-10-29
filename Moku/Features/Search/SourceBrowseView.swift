import SwiftUI

/// Desktop SourceTab for one source: its popular titles, a search inside the
/// source, and Load more while the source reports another page.
struct SourceBrowseView: View {
    let source: SourceExtension
    let openEntry: (MediaEntry) -> Void
    let close: () -> Void
    @Environment(LibraryStore.self) private var library
    @State private var query = ""
    @State private var submitted = ""
    @State private var items: [MediaEntry] = []
    @State private var page = 1
    @State private var hasNext = false
    @State private var loading = false
    @State private var error: String?
    @State private var generation = 0

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    TextField("Search \(source.displayName)…", text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await load(reset: true) } }
                        .generalInput()
                        .accessibilityIdentifier("source.search")
                    if !submitted.isEmpty {
                        Button("Clear") {
                            query = ""
                            Task { await load(reset: true) }
                        }
                        .buttonStyle(GeneralTextButtonStyle())
                    }
                }
                Text(submitted.isEmpty ? "Popular" : "Results for “\(submitted)”")
                    .font(.headline)
                if let error, items.isEmpty {
                    VStack(spacing: 12) {
                        Text(error).font(.subheadline).foregroundStyle(GeneralStyle.label)
                            .multilineTextAlignment(.center)
                        Button("Try again") { Task { await load(reset: true) } }
                            .buttonStyle(GeneralTextButtonStyle())
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else if items.isEmpty && loading {
                    ContentSkeleton(style: .library, count: 6)
                } else if items.isEmpty {
                    Text("Nothing found.").font(.subheadline).foregroundStyle(GeneralStyle.label)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(items) { item in
                            Button { openEntry(item) } label: { card(item) }
                                .buttonStyle(.plain)
                        }
                    }
                    if hasNext {
                        Button(loading ? "Loading…" : "Load more") { Task { await load(reset: false) } }
                            .buttonStyle(GeneralTextButtonStyle())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .disabled(loading)
                            .accessibilityIdentifier("source.loadMore")
                    }
                }
            }
            .padding(.horizontal, NavigationStyle.pagePadding).padding(.vertical, 12)
        }
        .refreshable { await load(reset: true) }
        .safeAreaInset(edge: .top, spacing: 0) {
            BackHeader(title: source.displayName, backLabel: "Back to Browse", identifier: "source.back", back: close)
                .background(NavigationStyle.background)
        }
        .background(NavigationStyle.background.ignoresSafeArea())
        .task(id: source.packageName) { await load(reset: true) }
    }

    private func card(_ item: MediaEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(url: item.coverURL, symbol: item.media.symbol)
                .aspectRatio(2 / 3, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if library.contains(item) {
                        Text("Saved").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(NavigationStyle.accent, in: Capsule())
                            .foregroundStyle(NavigationStyle.background)
                            .padding(6)
                    }
                }
            Text(item.title).font(.caption).lineLimit(2).foregroundStyle(GeneralStyle.text)
        }
        .accessibilityElement(children: .combine)
    }

    private func load(reset: Bool) async {
        struct Page: Decodable, Sendable {
            struct Item: Decodable, Sendable {
                let id: String
                let externalId: String
                let title: String
                let contentType: String
                let thumbnailUrl: String?
            }
            let results: [Item]
            let hasNextPage: Bool
        }
        struct Response: Decodable, Sendable {
            let popularManga: Page?
            let search: Page?
        }
        if reset {
            submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
            page = 1
        } else {
            guard hasNext, !loading else { return }
            page += 1
        }
        generation += 1
        let current = generation
        loading = true
        defer { if generation == current { loading = false } }
        let id = BackendAPI.literal(source.packageName)
        let fields = "results { id externalId title contentType thumbnailUrl } hasNextPage"
        let request = submitted.isEmpty
            ? "{ popularManga(extensionId: \(id), page: \(page)) { \(fields) } }"
            : "{ search(extensionId: \(id), query: \(BackendAPI.literal(submitted)), page: \(page)) { \(fields) } }"
        do {
            let response: Response = try await BackendAPI.shared.graphql(request, cacheFor: 60)
            guard generation == current else { return }
            let result = response.popularManga ?? response.search
            let fresh = (result?.results ?? []).map {
                MediaEntry(id: $0.id, title: $0.title, media: source.media, sourceName: source.displayName,
                           coverURL: BackendAPI.coverURL($0.thumbnailUrl),
                           extensionID: source.packageName, externalID: $0.externalId)
            }
            let known = reset ? [] : Set(items.map(\.id))
            items = (reset ? [] : items) + fresh.filter { !known.contains($0.id) }
            hasNext = result?.hasNextPage ?? false
            error = nil
        } catch {
            guard generation == current else { return }
            if !reset { page -= 1 }
            self.error = (error as? EmbeddedSearchError)?.errorDescription
                ?? "The source couldn’t be reached. It may be down or limiting requests."
            if !items.isEmpty { Toaster.shared.show("Couldn’t load more", detail: self.error, kind: .error) }
        }
    }
}

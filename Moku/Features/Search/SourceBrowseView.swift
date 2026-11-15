import SwiftUI

/// One source's popular titles, an in-source search, and Load more while the source has another page.
struct SourceBrowseView: View {
    let source: SourceExtension
    let openEntry: (MediaEntry) -> Void
    let close: () -> Void
    @Environment(\.presentSourceVerification) private var verify
    @State private var query = ""
    @State private var submitted = ""
    @State private var items: [MediaEntry] = []
    @State private var page = 1
    @State private var hasNext = false
    @State private var loading = false
    @State private var error: String?
    @State private var generation = 0
    /// Typed searches hide titles with no chapters at the source, as in Search.
    @State private var hiddenEmpty = 0
    @State private var feed: Feed = .popular

    private enum Feed: String, CaseIterable, Identifiable {
        case popular = "Popular", latest = "Latest"
        var id: Self { self }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if submitted.isEmpty && source.supportsLatest == true {
                    Picker("Feed", selection: $feed) {
                        ForEach(Feed.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("source.feed")
                } else {
                    Text(submitted.isEmpty ? "Popular" : "Results for “\(submitted)”")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                if hiddenEmpty > 0 {
                    Text("Hid \(hiddenEmpty) title\(hiddenEmpty == 1 ? "" : "s") with no chapters at the source.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error, items.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn’t Load", systemImage: "wifi.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        if BrowserVerification.isChallenge(error) {
                            Button("Verify in Browser") {
                                verify(extensionID: source.packageName, url: nil, sourceName: source.displayName) {
                                    Task { await load(reset: true) }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("source.verify")
                        }
                        Button("Try Again") { Task { await load(reset: true) } }
                            .buttonStyle(.bordered)
                    }
                } else if items.isEmpty && loading {
                    ContentSkeleton(style: .library, count: 6)
                } else if items.isEmpty {
                    ContentUnavailableView(
                        submitted.isEmpty ? "Nothing Here" : "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("Nothing found."))
                } else {
                    PosterGrid(entries: items, identifier: "source.item", open: openEntry)
                    if hasNext {
                        Button { Task { await load(reset: false) } } label: {
                            Group {
                                if loading { ProgressView() } else { Text("Load More") }
                            }
                            .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .disabled(loading)
                        .accessibilityIdentifier("source.loadMore")
                    }
                }
            }
            .padding(.horizontal, NavigationStyle.pagePadding).padding(.vertical, 12)
        }
        .refreshable { await load(reset: true) }
        .navigationTitle(source.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query, placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search \(source.displayName)")
        .onSubmit(of: .search) { Task { await load(reset: true) } }
        .onChange(of: query) { _, value in
            // Clearing the field returns to the source's popular titles.
            if value.isEmpty, !submitted.isEmpty { Task { await load(reset: true) } }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .background(NavigationStyle.background.ignoresSafeArea())
        .task(id: source.packageName) { await load(reset: true) }
        .onChange(of: feed) { Task { await load(reset: true) } }
    }

    private func hideEmpty(_ entries: [MediaEntry], generation current: Int) async {
        await withTaskGroup(of: (String, ContentProbe.Verdict).self) { group in
            for entry in entries {
                group.addTask {
                    (entry.id, await ContentProbe.shared.verdict(for: entry) { try await LiveMediaRepository.shared.chapterCount($0) })
                }
            }
            for await (id, verdict) in group where verdict == .empty {
                guard generation == current, items.contains(where: { $0.id == id }) else { continue }
                items.removeAll { $0.id == id }
                hiddenEmpty += 1
            }
        }
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
            let latestUpdates: Page?
            let search: Page?
        }
        if reset {
            submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
            page = 1
            hiddenEmpty = 0
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
        let listing = feed == .latest && source.supportsLatest == true ? "latestUpdates" : "popularManga"
        let request = submitted.isEmpty
            ? "{ \(listing)(extensionId: \(id), page: \(page)) { \(fields) } }"
            : "{ search(extensionId: \(id), query: \(BackendAPI.literal(submitted)), page: \(page)) { \(fields) } }"
        do {
            let response: Response = try await BackendAPI.shared.graphql(request, cacheFor: 60)
            guard generation == current else { return }
            let result = response.popularManga ?? response.latestUpdates ?? response.search
            let fresh = (result?.results ?? []).map {
                MediaEntry(id: $0.id, title: $0.title, media: source.media, sourceName: source.displayName,
                           coverURL: BackendAPI.coverURL($0.thumbnailUrl),
                           extensionID: source.packageName, externalID: $0.externalId)
            }
            let known = reset ? [] : Set(items.map(\.id))
            items = (reset ? [] : items) + fresh.filter { !known.contains($0.id) }
            hasNext = result?.hasNextPage ?? false
            error = nil
            if !submitted.isEmpty { Task { await hideEmpty(fresh, generation: current) } }
        } catch {
            guard generation == current else { return }
            if !reset { page -= 1 }
            self.error = (error as? EmbeddedSearchError)?.errorDescription
                ?? "The source couldn’t be reached. It may be down or limiting requests."
            if !items.isEmpty { Toaster.shared.show("Couldn’t load more", detail: self.error, kind: .error) }
        }
    }
}

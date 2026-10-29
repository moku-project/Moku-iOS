import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    enum Panel { case filters, sort }
    enum State: Equatable {
        case idle, loading
        case results([MediaEntry])
        case unavailable
        case failed(String)
    }

    private(set) var popular: [MediaEntry] = [] { didSet { shelfCache = nil } }
    private(set) var latest: [MediaEntry] = [] { didSet { shelfCache = nil } }
    private(set) var recommendations: [MediaEntry] = [] { didSet { shelfCache = nil } }
    private(set) var discoveryLoading = false
    private(set) var discoveryMessage: String?
    private(set) var recommendationMessage: String?
    @ObservationIgnored private var discoveryGeneration = 0

    func selectMode(_ mode: ContentMode) {
        guard mode != options.media else { return }
        draft = options
        draft.media = mode
        draft.sourceID = nil
        if draft.method == .source { draft.method = .keyword }
        apply()
    }

    @ObservationIgnored private var discoveryLoadedAt: Date?
    @ObservationIgnored private var discoveryLoadedOptions: SearchOptions?
    @ObservationIgnored private var discoveryLoadedContext = ""

    func loadDiscovery(snapshot: HomeSnapshot, saved: [MediaEntry], refreshToken: Int = 0) async {
        guard !Task.isCancelled else { return }
        let context = "\(refreshToken)-\(snapshot.sessions.count)-\(snapshot.sessions.map(\.endedAt).max()?.timeIntervalSinceReferenceDate ?? 0)-\(saved.map(\.id))"
        if discoveryLoadedOptions == options, discoveryLoadedContext == context,
           let discoveryLoadedAt, Date.now.timeIntervalSince(discoveryLoadedAt) < 300 {
            return
        }
        let sameMode = discoveryLoadedOptions == options
        discoveryGeneration += 1
        let generation = discoveryGeneration
        let selectedOptions = options
        // Keep usable shelves visible while refreshing the same selection.
        if !sameMode {
            popular = []
            latest = []
            recommendations = []
        }
        discoveryMessage = nil
        recommendationMessage = nil
        discoveryLoading = true
        defer { if generation == discoveryGeneration { discoveryLoading = false } }
        async let fresh: Void = loadLatest(options: selectedOptions, generation: generation)
        await loadPopularDiscovery(snapshot: snapshot, saved: saved, selectedOptions: selectedOptions, generation: generation)
        await fresh
        guard !Task.isCancelled, generation == discoveryGeneration else { return }
        if discoveryMessage == nil || !popular.isEmpty {
            discoveryLoadedAt = .now
            discoveryLoadedOptions = selectedOptions
            discoveryLoadedContext = context
        }
    }

    private func loadLatest(options: SearchOptions, generation: Int) async {
        do {
            let page = try await repository.latest(options: options)
            try Task.checkCancellation()
            guard generation == discoveryGeneration else { return }
            latest = page.entries
        } catch {
            // Optional shelves must never hide the primary recommendations.
        }
    }

    @ObservationIgnored private var shelfCache: [[DiscoveryShelf]]?
    var discoveryPairs: [[DiscoveryShelf]] {
        // Track shelf dependencies even when the derived presentation is cached.
        let recommended = recommendations, popular = popular, latest = latest
        if let shelfCache { return shelfCache }
        let result = DiscoveryRotation.pairs(recommended: recommended, popular: popular, latest: latest)
        shelfCache = result
        return result
    }

    private func loadPopularDiscovery(snapshot: HomeSnapshot, saved: [MediaEntry], selectedOptions: SearchOptions, generation: Int) async {
        do {
            let page = try await repository.popular(options: selectedOptions)
            try Task.checkCancellation()
            guard generation == discoveryGeneration else { return }
            popular = page.entries
            discoveryMessage = page.message
            let readIDs = Set(snapshot.sessions.map(\.entryID))
            let seeds = Array(snapshot.entries.filter {
                readIDs.contains($0.id)
                    && (selectedOptions.media == .all || $0.sourceEntry?.media == selectedOptions.media
                        || $0.media.lowercased() == selectedOptions.media.rawValue)
            }.prefix(12))
            let seedGenres = try await concurrentMap(seeds, limit: 3) { [repository] seed in
                if !seed.genres.isEmpty { return seed.genres }
                guard let entry = seed.sourceEntry else { return [] }
                do { return try await repository.genres(for: entry) }
                catch is CancellationError { throw CancellationError() }
                catch { return [] }
            }
            let weights = DiscoveryRanking.weights(seedGenres)
            guard !weights.isEmpty else {
                recommendationMessage = "Read a few titles to get recommendations based on your favorite genres."
                return
            }
            let excluded = saved + snapshot.entries.compactMap(\.sourceEntry)
            let excludedIDs = Set(saved.map(\.id)).union(readIDs)
            let excludedKeys = Set(excluded.map(DiscoveryRanking.key))
            let candidates = page.entries.filter {
                !excludedIDs.contains($0.id) && !excludedKeys.contains(DiscoveryRanking.key($0))
            }
            let scored = try await concurrentMap(candidates, limit: 3) { [repository] entry in
                do {
                    let genres = try await repository.genres(for: entry)
                    return (entry, DiscoveryRanking.score(genres, weights: weights))
                } catch is CancellationError { throw CancellationError() }
                catch { return (entry, 0) }
            }
            try Task.checkCancellation()
            guard generation == discoveryGeneration else { return }
            recommendations = scored.enumerated().filter { $0.element.1 > 0 }
                .sorted { a, b in a.element.1 == b.element.1 ? a.offset < b.offset : a.element.1 > b.element.1 }
                .prefix(12).map { $0.element.0 }
            if recommendations.isEmpty {
                recommendationMessage = "No similar titles found yet. Explore popular titles below."
            }
        } catch is CancellationError {
        } catch {
            guard generation == discoveryGeneration else { return }
            discoveryMessage = "Couldn’t load discoveries. Check your connection and try again."
        }
    }

    let isLibrary: Bool

    var query = "" {
        didSet {
            if query != oldValue { scheduleSearch() }
        }
    }
    private(set) var options: SearchOptions
    var draft: SearchOptions
    private(set) var panel: Panel?
    private(set) var state: State = .idle
    private(set) var loadingMore = false
    private(set) var canLoadMore = false
    @ObservationIgnored private var lastRequest: SearchRequest?
    private(set) var isSearching = false
    private(set) var searchMessage: String?
    private(set) var sources: [SearchSource] = []
    private(set) var sourceMessage: String?
    private(set) var sourcesAreLoading = false
    private(set) var recentSearches: [SearchHistoryItem] = []
    private(set) var historyLoading = false
    private(set) var historyError: String?
    @ObservationIgnored private var historyStore: SearchHistoryStore?
    @ObservationIgnored private let repository: any SearchRepository
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var sourceTask: Task<[SearchSource], Error>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let debounce: Duration
    /// Typed-search results confirmed to have no chapters this search.
    private(set) var hiddenEmpty = 0
    @ObservationIgnored private let probe: ContentProbe
    @ObservationIgnored private var emptyIDs: Set<String> = []
    @ObservationIgnored private var probedIDs: Set<String> = []
    @ObservationIgnored private var probeTasks: [Task<Void, Never>] = []

    init(
        repository: any SearchRepository, media: ContentMode = .all, language: String? = nil,
        debounce: Duration = .milliseconds(350), isLibrary: Bool = false,
        probe: ContentProbe = .shared
    ) {
        self.isLibrary = isLibrary
        self.probe = probe
        self.debounce = debounce
        self.repository = repository
        let initial = SearchOptions(media: media, language: language)
        options = initial
        draft = initial
    }

    var canSubmit: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !options.genres.isEmpty || !options.statuses.subtracting([.any]).isEmpty
    }

    var canApply: Bool { draft.method != .source || draft.sourceID != nil }

    func loadHistory(_ store: SearchHistoryStore?) async {
        historyStore = store
        guard let store else { return }
        historyLoading = true
        defer { historyLoading = false }
        do {
            recentSearches = try await store.recent()
            historyError = nil
        } catch { historyError = error.localizedDescription }
    }

    func removeHistory(_ item: SearchHistoryItem? = nil) async {
        guard let historyStore else { return }
        do {
            recentSearches = try await historyStore.remove(id: item?.id)
            historyError = nil
        } catch { historyError = error.localizedDescription }
    }

    private func remember(_ query: String) async {
        guard let historyStore else { return }
        do {
            recentSearches = try await historyStore.record(query)
            historyError = nil
        } catch { historyError = "Couldn’t save this search. Your results are still available." }
    }

    var visibleSources: [SearchSource] {
        sources.filter {
            (draft.media == .all || $0.media == .all || $0.media == draft.media)
                && (draft.language == nil || $0.language == "all" || $0.language == draft.language)
        }.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    // "all" describes a multilingual source, not a selectable language.
    var languages: [String] {
        Array(Set(sources.map(\.language).filter { !$0.isEmpty && $0 != "all" })).sorted()
    }

    func loadSources() async {
        let task = sourceTask ?? Task { [repository] in try await repository.sources() }
        sourceTask = task
        sourcesAreLoading = true
        defer {
            sourcesAreLoading = false
            sourceTask = nil
        }
        do {
            let loaded = try await task.value
            try Task.checkCancellation()
            sources = loaded
            sourceMessage =
                sources.isEmpty
                ? (isLibrary
                    ? "Sources appear here when you save titles."
                    : "No sources installed. Open Extensions from the More menu to add one.") : nil
        } catch is CancellationError {
        } catch SearchFailure.notConnected {
            sourceMessage = "Sources couldn’t load. Try again in a moment."
        } catch {
            sourceMessage =
                (error as? EmbeddedSearchError)?.errorDescription
                ?? "Couldn’t load sources. Check your connection and try again."
        }
    }

    func open(_ panel: Panel) {
        requestTask?.cancel()
        generation += 1
        isSearching = false
        if state == .loading { state = .idle }
        draft = options
        self.panel = panel
    }

    func cancelPanel() {
        draft = options
        panel = nil
    }

    func resetFilters() {
        let sort = draft.sort
        draft = SearchOptions()
        draft.sort = sort
    }

    func validateSource() {
        if let id = draft.sourceID, !visibleSources.contains(where: { $0.id == id }) {
            draft.sourceID = nil
        }
    }

    func apply() {
        guard canApply else { return }
        options = draft
        panel = nil
        invalidate()
        submit()
    }

    private func scheduleSearch() {
        invalidate()
        guard panel == nil, canSubmit else { return }
        let current = generation
        let delay = debounce
        requestTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard let self, !Task.isCancelled, self.generation == current else { return }
                self.submit()
            } catch is CancellationError {
            } catch {
                // Sleeping is the only throwing operation; cancellation needs no UI.
            }
        }
    }

    func submit() {
        guard panel == nil, canSubmit else { return }
        requestTask?.cancel()
        resetProbes()
        generation += 1
        let current = generation
        let request = SearchRequest(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines), options: options
        )
        state = .loading
        isSearching = true
        searchMessage = nil
        canLoadMore = false
        requestTask = Task { [weak self, repository] in
            defer {
                if let self, self.generation == current { self.isSearching = false }
            }
            do {
                let entries = try await repository.search(request) { [weak self] entries in
                    await self?.receive(entries, request: request, generation: current)
                }
                guard let self, !Task.isCancelled, self.generation == current else { return }
                var sorted = await Self.sorted(entries, by: request.options.sort)
                // Desktop genre drill: matching library titles come first.
                if !request.options.genres.isEmpty {
                    let saved = await Self.libraryMatches(request.options)
                    let ids = Set(saved.map(\.id))
                    let keys = Set(saved.compactMap { item in item.externalID.map { "\(item.extensionID ?? ""):\($0)" } })
                    sorted = saved + sorted.filter {
                        !ids.contains($0.id) && !keys.contains("\($0.extensionID ?? ""):\($0.externalID ?? "-")")
                    }
                }
                guard !Task.isCancelled, self.generation == current else { return }
                self.state = .results(sorted.filter { !self.emptyIDs.contains($0.id) })
                self.probeForContent(sorted, request: request, generation: current)
                self.lastRequest = request
                self.canLoadMore = !entries.isEmpty && !self.isLibrary
                await self.remember(request.query)
            } catch is CancellationError {
            } catch {
                guard let self, !Task.isCancelled, self.generation == current else { return }
                if case .results(let entries) = self.state, !entries.isEmpty {
                    self.searchMessage = "Some sources couldn’t finish. Showing available results."
                    return
                }
                self.state =
                    error is SearchFailure
                    ? .unavailable
                    : .failed(
                        (error as? EmbeddedSearchError)?.errorDescription
                            ?? "Couldn’t search. Check your connection and try again.")
            }
        }
    }

    @ObservationIgnored private var resumeSearch = false
    func setActive(_ active: Bool) {
        if active {
            if resumeSearch { resumeSearch = false; submit() }
        } else {
            resumeSearch = resumeSearch || isSearching || requestTask != nil && state == .idle && canSubmit
            requestTask?.cancel()
            requestTask = nil
            generation += 1
            isSearching = false
            if state == .loading { state = .idle }
        }
    }

    func invalidate() {
        requestTask?.cancel()
        resetProbes()
        generation += 1
        state = .idle
        isSearching = false
        searchMessage = nil
    }

    /// Next page from every source that answered, appended without duplicates.
    func loadMore() async {
        guard var request = lastRequest, !loadingMore, case .results(let current) = state else { return }
        request.page += 1
        loadingMore = true
        defer { loadingMore = false }
        let generation = generation
        do {
            let more = try await repository.search(request)
            guard self.generation == generation else { return }
            let known = Set(current.map(\.id))
            let fresh = more.filter { !known.contains($0.id) }
            canLoadMore = !fresh.isEmpty
            lastRequest = request
            state = .results(current + (await Self.sorted(fresh, by: request.options.sort)))
            probeForContent(fresh, request: request, generation: generation)
        } catch is CancellationError {
        } catch {
            guard self.generation == generation else { return }
            Toaster.shared.show("Couldn’t load more results", detail: "Check your connection and try again.", kind: .error)
        }
    }

    private func receive(_ entries: [MediaEntry], request: SearchRequest, generation: Int) async {
        guard !Task.isCancelled, self.generation == generation, !entries.isEmpty else { return }
        let sorted = await Self.sorted(entries, by: request.options.sort)
        guard !Task.isCancelled, self.generation == generation else { return }
        state = .results(sorted.filter { !emptyIDs.contains($0.id) })
        probeForContent(sorted, request: request, generation: generation)
    }

    /// Forward fetching for typed searches: each result's chapters are checked in
    /// the background, and titles confirmed empty at their source are removed.
    /// Results stay visible while checking, and a failed check keeps the title.
    private func probeForContent(_ entries: [MediaEntry], request: SearchRequest, generation: Int) {
        guard request.options.hidesEmpty, !request.query.isEmpty, !isLibrary else { return }
        let fresh = entries.filter { probedIDs.insert($0.id).inserted }
        guard !fresh.isEmpty else { return }
        let probe = probe, repository = repository
        probeTasks.append(Task { [weak self] in
            await withTaskGroup(of: (String, ContentProbe.Verdict).self) { group in
                for entry in fresh {
                    group.addTask {
                        (entry.id, await probe.verdict(for: entry) { try await repository.chapterCount($0) })
                    }
                }
                for await (id, verdict) in group where verdict == .empty {
                    guard let self, !Task.isCancelled, self.generation == generation else { return }
                    self.hide(id)
                }
            }
        })
    }

    private func hide(_ id: String) {
        guard emptyIDs.insert(id).inserted, case .results(let entries) = state else { return }
        let remaining = entries.filter { $0.id != id }
        guard remaining.count != entries.count else { return }
        state = .results(remaining)
        hiddenEmpty += 1
    }

    private func resetProbes() {
        for task in probeTasks { task.cancel() }
        probeTasks = []
        probedIDs = []
        emptyIDs = []
        hiddenEmpty = 0
    }

    /// Library titles carrying the chosen genres: all of them, or any one for "match any".
    nonisolated static func libraryMatches(_ options: SearchOptions) async -> [MediaEntry] {
        struct Response: Decodable, Sendable {
            struct Page: Decodable, Sendable {
                struct Item: Decodable, Sendable {
                    let id: String
                    let title: String
                    let contentType: String
                    let sourceName: String
                    let thumbnailUrl: String?
                    let extensionId: String?
                    let externalId: String
                    let genres: [String]
                }
                let items: [Item]
            }
            let library: Page
        }
        let type = options.media == .all ? "" : "contentType: \(options.media.graphQLType)"
        guard let response: Response = try? await BackendAPI.shared.graphql(
            "{ library(filter: { \(type) }, limit: 1000) { items { id title contentType sourceName thumbnailUrl extensionId externalId genres } } }",
            cacheFor: 30, requiresSourceRuntime: false) else { return [] }
        let wanted = Set(options.genres.map { $0.lowercased() })
        return response.library.items.filter { item in
            let genres = Set(item.genres.map { $0.lowercased() })
            return options.match == .all ? wanted.isSubset(of: genres) : !wanted.isDisjoint(with: genres)
        }.map {
            MediaEntry(id: $0.id, title: $0.title,
                       media: $0.contentType == "ANIME" ? .anime : $0.contentType == "NOVEL" ? .novels : .manga,
                       sourceName: $0.sourceName, coverURL: BackendAPI.coverURL($0.thumbnailUrl),
                       extensionID: $0.extensionId, externalID: $0.externalId)
        }
    }

    private nonisolated static func sorted(_ entries: [MediaEntry], by sort: SearchOptions.Sort)
        async -> [MediaEntry]
    {
        guard sort != .sourceOrder else { return entries }
        return entries.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            if order == .orderedSame { return $0.id < $1.id }
            return sort == .titleAscending
                ? order == .orderedAscending : order == .orderedDescending
        }
    }
}

/// One vote per genre per read title; repeated sessions do not overpower other tastes.
enum DiscoveryRanking {
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func key(_ entry: MediaEntry) -> String { entry.media.rawValue + ":" + normalized(entry.title) }
    static func weights(_ titles: [[String]]) -> [String: Int] {
        var result: [String: Int] = [:]
        for genres in titles {
            for genre in Set(genres.map(normalized)) where !genre.isEmpty { result[genre, default: 0] += 1 }
        }
        return result
    }
    static func score(_ genres: [String], weights: [String: Int]) -> Int {
        Set(genres.map(normalized)).reduce(0) { $0 + weights[$1, default: 0] }
    }
}

struct DiscoveryShelf: Identifiable, Equatable {
    let id: String
    let title: String
    let entries: [MediaEntry]
}

/// Each rotation shows a distinct set of titles, including across source aliases.
enum DiscoveryRotation {
    static func pairs(recommended: [MediaEntry], popular: [MediaEntry], latest: [MediaEntry]) -> [[DiscoveryShelf]] {
        var seen = Set<String>()
        func take(_ entries: [MediaEntry], limit: Int = 12) -> [MediaEntry] {
            var result: [MediaEntry] = []
            for entry in entries where !seen.contains(DiscoveryRanking.key(entry)) {
                seen.insert(DiscoveryRanking.key(entry))
                result.append(entry)
                if result.count == limit { break }
            }
            return result
        }
        let first = [
            DiscoveryShelf(id: "recommended", title: "Recommended for you", entries: take(recommended)),
            DiscoveryShelf(id: "popular", title: "Popular right now", entries: take(popular)),
        ]
        // Reserve some unseen titles for the second shelf when the latest feed
        // is the only available source of extra titles.
        let unseenLatest = latest.filter { !seen.contains(DiscoveryRanking.key($0)) }
        let fresh = take(unseenLatest, limit: min(12, max(1, unseenLatest.count / 2)))
        let explore = take(popular + latest)
        guard !fresh.isEmpty, !explore.isEmpty else { return [first] }
        return [first, [
            DiscoveryShelf(id: "latest", title: "Latest updates", entries: fresh),
            DiscoveryShelf(id: "explore", title: "More to explore", entries: explore),
        ]]
    }
}

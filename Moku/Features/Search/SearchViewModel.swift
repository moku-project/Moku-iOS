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

    private(set) var popular: [MediaEntry] = []
    private(set) var popularLoading = false
    private(set) var popularMessage: String?
    @ObservationIgnored private var popularLoaded: (options: SearchOptions, at: Date)?

    func selectMode(_ mode: ContentMode) {
        guard mode != options.media else { return }
        draft = options
        draft.media = mode
        draft.sourceID = nil
        if draft.method == .source { draft.method = .keyword }
        apply()
    }

    /// Page one of every matching source's popular list, merged; reused for five minutes unless forced.
    func loadPopular(force: Bool = false) async {
        let selected = options
        if !force, let popularLoaded, popularLoaded.options == selected,
           Date.now.timeIntervalSince(popularLoaded.at) < 300 { return }
        guard !Task.isCancelled else { return }
        if popularLoaded?.options != selected { popular = [] }
        popularLoading = true
        popularMessage = nil
        defer { if options == selected { popularLoading = false } }
        do {
            let page = try await repository.popular(options: selected)
            try Task.checkCancellation()
            guard options == selected else { return }
            popular = page.entries
            popularMessage = page.message
            popularLoaded = (selected, .now)
        } catch is CancellationError {
        } catch {
            guard options == selected else { return }
            popularMessage = (error as? EmbeddedSearchError)?.errorDescription
                ?? "Couldn’t load popular titles. Check your connection and try again."
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
                    : "No sources installed. Open Settings → Extensions to add one.") : nil
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
                // Genre drill: matching library titles come first.
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
    }

    /// After every source answers, checks results' chapters in the background and drops confirmed-empty ones; failures keep the title.
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

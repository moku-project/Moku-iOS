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

    init(
        repository: any SearchRepository, media: ContentMode = .all, language: String? = nil,
        debounce: Duration = .milliseconds(350), isLibrary: Bool = false
    ) {
        self.isLibrary = isLibrary
        self.debounce = debounce
        self.repository = repository
        let initial = SearchOptions(media: media, language: language)
        options = initial
        draft = initial
    }

    var canSubmit: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (options.method == .tags && !options.genres.isEmpty)
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
            sourceMessage = "Sources are not available yet."
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
        generation += 1
        let current = generation
        let request = SearchRequest(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines), options: options
        )
        state = .loading
        isSearching = true
        searchMessage = nil
        requestTask = Task { [weak self, repository] in
            defer {
                if let self, self.generation == current { self.isSearching = false }
            }
            do {
                let entries = try await repository.search(request) { [weak self] entries in
                    await self?.receive(entries, request: request, generation: current)
                }
                guard let self, !Task.isCancelled, self.generation == current else { return }
                self.state = .results(Self.sorted(entries, by: request.options.sort))
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

    func invalidate() {
        requestTask?.cancel()
        generation += 1
        state = .idle
        isSearching = false
        searchMessage = nil
    }

    private func receive(_ entries: [MediaEntry], request: SearchRequest, generation: Int) {
        guard !Task.isCancelled, self.generation == generation, !entries.isEmpty else { return }
        state = .results(Self.sorted(entries, by: request.options.sort))
    }

    private static func sorted(_ entries: [MediaEntry], by sort: SearchOptions.Sort)
        -> [MediaEntry]
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

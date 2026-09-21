import Foundation
import Testing

@testable import Moku

private actor SearchSpy: SearchRepository {
    private(set) var requests: [SearchRequest] = []
    let delay: Bool
    init(delay: Bool = false) { self.delay = delay }
    func sources() async throws -> [SearchSource] {
        [SearchSource(id: "one", name: "One", language: "en", media: .manga, isPinned: false)]
    }
    func search(_ request: SearchRequest) async throws -> [MediaEntry] {
        requests.append(request)
        if delay { try? await Task.sleep(for: .milliseconds(60)) }
        return [
            MediaEntry(id: "z", title: "Zulu", media: .manga, sourceName: "One", coverURL: nil),
            MediaEntry(id: "a", title: "Alpha", media: .manga, sourceName: "One", coverURL: nil),
        ]
    }
}

@MainActor
struct SearchModelTests {
    @Test func draftsDoNotSearchAndCancelDoesNotCommit() async {
        let spy = SearchSpy()
        let model = SearchViewModel(repository: spy)
        model.query = "moon"
        model.open(.filters)
        model.draft.genres.insert("Fantasy")
        model.submit()
        #expect(await spy.requests.isEmpty)
        #expect(model.state == .idle)
        model.cancelPanel()
        #expect(model.options.genres.isEmpty)
        #expect(model.draft == model.options)
    }

    @Test func applyCommitsAllOptionsAndSortsReturnedEntries() async throws {
        let spy = SearchSpy()
        let model = SearchViewModel(repository: spy)
        model.query = "  moon  "
        model.open(.filters)
        model.draft.genres = ["Fantasy", "Romance"]
        model.draft.match = .any
        model.draft.statuses = [.ongoing, .hiatus]
        model.draft.language = "en"
        model.draft.sourceID = "one"
        model.draft.sort = .titleAscending
        model.apply()
        for _ in 0..<100 where model.state == .loading {
            try await Task.sleep(for: .milliseconds(5))
        }
        let requests = await spy.requests
        #expect(requests.count == 1)
        #expect(requests.first?.query == "moon")
        #expect(requests.first?.options == model.options)
        guard case .results(let entries) = model.state else {
            Issue.record("Expected results")
            return
        }
        #expect(entries.map(\.id) == ["a", "z"])
    }

    @Test func editingQueryDiscardsAnOldResponse() async throws {
        let spy = SearchSpy(delay: true)
        let model = SearchViewModel(repository: spy)
        model.query = "old"
        model.submit()
        for _ in 0..<100 {
            if !(await spy.requests.isEmpty) { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        model.query = "new"
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state == .idle)
        #expect(model.query == "new")
    }

    @Test func typingDebouncesAndSubmitDoesNotRepeat() async throws {
        let spy = SearchSpy()
        let model = SearchViewModel(repository: spy, debounce: .milliseconds(40))
        model.query = "r"
        model.query = "rent"
        model.query = "rent a girlfriend"
        #expect(await spy.requests.isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await spy.requests.map(\.query) == ["rent a girlfriend"])
        model.query = "another"
        model.submit()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await spy.requests.map(\.query) == ["rent a girlfriend", "another"])
    }

    @Test func clearingAndClosingCancelDebouncedSearch() async throws {
        let spy = SearchSpy()
        let model = SearchViewModel(repository: spy, debounce: .milliseconds(40))
        model.query = "clear me"
        model.query = "   "
        try await Task.sleep(for: .milliseconds(100))
        #expect(await spy.requests.isEmpty)
        #expect(model.state == .idle)
        model.query = "close me"
        model.invalidate()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await spy.requests.isEmpty)
    }

    @Test func sourceScopeCannotKeepAnIncompatibleSelection() async {
        let model = SearchViewModel(repository: SearchSpy())
        await model.loadSources()
        model.open(.filters)
        model.draft.method = .source
        model.draft.sourceID = "one"
        model.draft.media = .anime
        model.validateSource()
        #expect(model.draft.sourceID == nil)
        #expect(!model.canApply)
        model.apply()
        #expect(model.panel == .filters)
    }
}

private actor SuspendedSources: SearchRepository {
    private var continuation: CheckedContinuation<[SearchSource], Never>?
    private(set) var calls = 0
    func sources() async throws -> [SearchSource] {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func search(_ request: SearchRequest) async throws -> [MediaEntry] { [] }
    func release() {
        continuation?.resume(returning: [
            SearchSource(
                id: "source", name: "Source", language: "en", media: .manga, isPinned: false)
        ])
        continuation = nil
    }
}

@MainActor
struct SearchStartupTests {
    @Test func openingModelDoesNotRequestSources() async {
        let repository = SuspendedSources()
        let model = SearchViewModel(repository: repository)
        #expect(model.state == .idle)
        #expect(await repository.calls == 0)
    }

    @Test func delayedSourcesDoNotBlockEditingOrClosingSearch() async {
        let repository = SuspendedSources()
        let model = SearchViewModel(repository: repository)
        let loading = Task { await model.loadSources() }
        while await repository.calls == 0 { await Task.yield() }
        #expect(model.sourcesAreLoading)
        model.query = "moon"
        model.open(.sort)
        model.invalidate()
        #expect(model.query == "moon")
        #expect(model.panel == .sort)
        loading.cancel()
        await repository.release()
        await loading.value
        #expect(model.sources.isEmpty)
        #expect(!model.sourcesAreLoading)
        #expect(model.sourceMessage == nil)
    }
}

private struct MultilingualSources: SearchRepository {
    func sources() async throws -> [SearchSource] {
        ["all", "en", "ja", "en"].enumerated().map { index, language in
            SearchSource(
                id: "\(index)", name: language, language: language,
                media: .manga, isPinned: false)
        }
    }
    func search(_ request: SearchRequest) async throws -> [MediaEntry] { [] }
}

@MainActor
struct SearchLanguageTests {
    @Test func multilingualSourcesAreNotLanguageChoicesButRemainEligible() async {
        let model = SearchViewModel(repository: MultilingualSources())
        await model.loadSources()
        #expect(model.languages == ["en", "ja"])
        model.open(.filters)
        model.draft.language = "ja"
        #expect(model.visibleSources.map(\.language).sorted() == ["all", "ja"])
        model.draft.language = nil
        #expect(model.visibleSources.count == 4)
    }
}

private actor ProgressiveSearchSpy: SearchRepository {
    private var updates: [String: @Sendable ([MediaEntry]) async -> Void] = [:]
    private var completions: [String: CheckedContinuation<[MediaEntry], any Error>] = [:]

    func sources() async throws -> [SearchSource] { [] }
    func search(_ request: SearchRequest) async throws -> [MediaEntry] { [] }
    func search(
        _ request: SearchRequest,
        onUpdate: @escaping @Sendable ([MediaEntry]) async -> Void
    ) async throws -> [MediaEntry] {
        updates[request.query] = onUpdate
        return try await withCheckedThrowingContinuation { completions[request.query] = $0 }
    }
    func isPending(_ query: String) -> Bool { completions[query] != nil }
    func publish(_ query: String, entries: [MediaEntry]) async { await updates[query]?(entries) }
    func finish(_ query: String, result: Result<[MediaEntry], any Error>) {
        completions.removeValue(forKey: query)?.resume(with: result)
        updates.removeValue(forKey: query)
    }
}

@MainActor
struct ProgressiveSearchTests {
    private let entries = [
        MediaEntry(id: "z", title: "Zulu", media: .manga, sourceName: "Fast", coverURL: nil),
        MediaEntry(id: "a", title: "Alpha", media: .manga, sourceName: "Fast", coverURL: nil),
    ]

    @Test func fastSourceAppearsBeforeCompletionAndSurvivesAnotherSourceFailure() async throws {
        let repository = ProgressiveSearchSpy()
        let model = SearchViewModel(repository: repository)
        model.query = "moon"
        model.open(.sort)
        model.draft.sort = .titleAscending
        model.apply()
        for _ in 0..<100 where !(await repository.isPending("moon")) {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await repository.isPending("moon"))
        await repository.publish("moon", entries: entries)
        #expect(model.state == .results(entries.reversed()))
        #expect(model.isSearching)
        await repository.finish("moon", result: .failure(SearchFailure.notConnected))
        for _ in 0..<100 where model.isSearching {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!model.isSearching)
        #expect(model.state == .results(entries.reversed()))
        #expect(model.searchMessage != nil)
    }

    @Test func staleProgressCannotReplaceAnEditedQuery() async throws {
        let repository = ProgressiveSearchSpy()
        let model = SearchViewModel(repository: repository, debounce: .seconds(60))
        model.query = "old"
        model.submit()
        for _ in 0..<100 where !(await repository.isPending("old")) {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await repository.isPending("old"))
        model.query = "new"
        await repository.publish("old", entries: entries)
        #expect(model.state == .idle)
        #expect(!model.isSearching)
        await repository.finish("old", result: .success(entries))
        model.invalidate()
    }
}

@MainActor
struct SearchHistoryModelTests {
    @Test func completedSearchIsRememberedButCancelledSearchIsNot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let history = SearchHistoryStore(url: root.appending(path: "history.sqlite"))
        let model = SearchViewModel(repository: SearchSpy(delay: true), debounce: .seconds(60))
        await model.loadHistory(history)
        model.query = "cancelled"
        model.submit()
        model.invalidate()
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await history.recent().isEmpty)
        model.query = "  Moon  "
        model.submit()
        for _ in 0..<200 where model.isSearching {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!model.isSearching)
        #expect(model.recentSearches.map(\.query) == ["Moon"])
        let freshModel = SearchViewModel(repository: SearchSpy())
        await freshModel.loadHistory(history)
        #expect(freshModel.recentSearches.map(\.query) == ["Moon"])
        await freshModel.removeHistory()
        #expect(try await history.recent().isEmpty)
    }
}

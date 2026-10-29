import Foundation
import Testing

@testable import Moku

@MainActor struct LibrarySearchTests {
    @Test func cachedResultsFollowFiltersAndItemChanges() {
        let model = LibraryViewModel()
        model.items = [
            LibraryItem(id: "a", title: "Alpha", media: .manga),
            LibraryItem(id: "b", title: "Beta", media: .anime),
        ]
        #expect(model.visible(mode: .all).map(\.id) == ["a", "b"])
        #expect(model.visible(mode: .manga).map(\.id) == ["a"])
        model.query = "beta"
        #expect(model.visible(mode: .all).map(\.id) == ["b"])
        model.query = ""
        model.ascending = false
        #expect(model.visible(mode: .all).map(\.id) == ["b", "a"])
        model.items.removeLast()
        #expect(model.visible(mode: .all).map(\.id) == ["a"])
    }

    @Test func readingIncludesAnUnfinishedFirstChapter() {
        let model = LibraryViewModel()
        model.items = [
            LibraryItem(id: "started", title: "Started", media: .manga,
                        totalUnits: 10, lastRead: .now),
            LibraryItem(id: "unread", title: "Unread", media: .manga, totalUnits: 10),
            LibraryItem(id: "finished", title: "Finished", media: .manga,
                        readUnits: 10, totalUnits: 10, lastRead: .now),
        ]
        model.tab = .reading
        #expect(model.visible(mode: .all).map(\.id) == ["started"])
        #expect(model.items[0].readUnits == 0)
        #expect(model.items[0].unread == 10)
        model.tab = .saved
        model.startedOnly = true
        #expect(Set(model.visible(mode: .all).map(\.id)) == ["started", "finished"])
    }

    @Test func searchIsLocalAndSourcesComeOnlyFromSavedTitles() async throws {
        let entries = [
            MediaEntry(
                id: "one", title: "Moon Garden", media: .manga, sourceName: "Saved Source",
                coverURL: nil, extensionID: "saved"),
            MediaEntry(
                id: "two", title: "Moon Novel", media: .novels, sourceName: "Saved Source",
                coverURL: nil, extensionID: "saved"),
            MediaEntry(
                id: "three", title: "Sun", media: .anime, sourceName: "Other", coverURL: nil),
        ]
        let repository = LibrarySearchRepository(entries: entries)
        let sources = try await repository.sources()
        #expect(sources.count == 2)
        #expect(sources.first?.media == .all)
        let model = SearchViewModel(repository: repository, debounce: .zero, isLibrary: true)
        await model.loadSources()
        model.query = "moon"
        model.submit()
        for _ in 0..<100 where model.state == .loading {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.state == .results(Array(entries.prefix(2))))
        model.open(.filters)
        model.draft.media = .novels
        #expect(model.visibleSources.map(\.id) == ["saved"])
        model.draft.sourceID = "saved"
        model.apply()
        for _ in 0..<100 where model.state == .loading {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.state == .results([entries[1]]))
        let missing = try await repository.search(
            SearchRequest(query: "missing", options: SearchOptions()))
        #expect(missing.isEmpty)
    }
}

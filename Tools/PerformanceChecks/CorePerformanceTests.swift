import Foundation
import Observation
import Testing
@testable import Moku

struct CorePerformanceTests {
    @MainActor @Test func inactiveLibraryDoesNotObserveUnrelatedTabSwitches() {
        let tabs = TabActivityStore()
        let library = tabs[.library]
        #expect(library.hasVisited && library.isActive)
        tabs.update(selection: .home, covered: false)
        let changed = ObservationFlag()
        withObservationTracking {
            _ = library.isActive
            _ = library.hasVisited
        } onChange: { changed.set() }
        for _ in 0..<100 {
            tabs.update(selection: .more, covered: false)
            tabs.update(selection: .downloads, covered: false)
            tabs.update(selection: .home, covered: false)
        }
        #expect(!changed.value)
        #expect(tabs[.library] === library)
        tabs.update(selection: .library, covered: false)
        #expect(changed.value)
        #expect(library.isActive && library.hasVisited)
    }

    @MainActor @Test func overlaysSuspendActivityWithoutDiscardingVisitedPages() {
        let tabs = TabActivityStore()
        tabs.update(selection: .home, covered: false)
        tabs.update(selection: .home, covered: true)
        #expect(AppTab.allCases.allSatisfy { !tabs[$0].isActive })
        #expect(tabs[.home].hasVisited && tabs[.library].hasVisited)
        #expect(!tabs[.browse].hasVisited)
        tabs.update(selection: .browse, covered: true)
        #expect(tabs[.browse].hasVisited && !tabs[.browse].isActive)
        tabs.update(selection: .browse, covered: false)
        #expect(AppTab.allCases.filter { tabs[$0].isActive } == [.browse])
    }

    @MainActor @Test func unchangedLibrarySettingsKeepPreparedResultsValid() async {
        let model = LibraryViewModel()
        model.items = [LibraryItem(id: "one", title: "One", media: .manga)]
        let expected = await model.prepareVisible(mode: .all)
        let revision = model.resultsRevision
        // These values are reapplied by appearance/preference callbacks.
        model.items = expected
        model.showAllInSaved = true
        model.hideCompletedInSaved = false
        model.disableAutoComplete = false
        model.folderEntryIDs = []
        model.tab = .saved
        model.folder = nil
        model.clearFilters()
        model.sort = .title
        model.ascending = true
        model.query = ""
        #expect(model.resultsRevision == revision)
        #expect(await model.prepareVisible(mode: .all) == expected)
        model.downloadedOnly = true
        #expect(model.resultsRevision == revision + 1)
        #expect(await model.prepareVisible(mode: .all).isEmpty)
    }

    @MainActor @Test func cancelledLibraryPreparationDoesNotPoisonTheNextVisit() async {
        let model = LibraryViewModel()
        model.items = (0..<2_000).map {
            LibraryItem(id: "\($0)", title: "Title \($0)", media: .manga)
        }
        let interrupted = Task { await model.prepareVisible(mode: .all) }
        interrupted.cancel()
        #expect(await interrupted.value.isEmpty)
        #expect(await model.prepareVisible(mode: .all).count == 2_000)
    }

    @MainActor @Test func rapidReaderEditsPersistTheLatestPositionAndSettings() async throws {
        let suite = "performance.reader.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReaderPreferences(defaults: defaults)
        for page in 1...250 {
            preferences.document.positions["series"] = ReaderPosition(chapterID: "chapter", page: page)
        }
        preferences.document.global.readingDirection = "rtl"
        preferences.toggleOverride("series")
        preferences.savePreset("Reading", mediaID: "series")
        await preferences.flush()
        let restored = ReaderPreferences(defaults: defaults)
        #expect(restored.document.positions["series"]?.page == 250)
        #expect(restored.settings(for: "series").readingDirection == "rtl")
        #expect(restored.document.presets.count == 1)
    }

    @MainActor @Test func coalescedHistoryPreservesLatestSessionAndPins() async throws {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HomeStore(fileURL: url)
        await store.load()
        let entry = HomeEntry(id: "title", title: "Title")
        var session = HomeSession(entryID: entry.id, chapterID: "one", page: 1,
                                  endedAt: .now, minutes: 1, completedUnits: 0)
        for page in 1...300 {
            session.page = page
            store.record(session, entry: entry)
        }
        store.pin(entry, slot: 2)
        await store.flush()
        let restored = HomeStore(fileURL: url)
        await restored.load()
        #expect(restored.snapshot.sessions.count == 1)
        #expect(restored.snapshot.sessions.first?.page == 300)
        #expect(restored.slots[2].isPinned)
        let revision = restored.snapshotRevision
        restored.updateEntry(entry)
        #expect(restored.snapshotRevision == revision)
    }

    @MainActor @Test func preparedLibraryMatchesFiltersAndInvalidatesCachedResults() async {
        let model = LibraryViewModel()
        model.items = (0..<2_000).map {
            LibraryItem(id: "\($0)", title: "Title \($0)", media: $0.isMultiple(of: 2) ? .manga : .anime,
                        readUnits: $0 % 4, totalUnits: 10, bookmarked: $0.isMultiple(of: 5))
        }
        model.bookmarkedOnly = true
        model.ascending = false
        let prepared = await model.prepareVisible(mode: .manga)
        #expect(prepared.map(\.id) == model.visible(mode: .manga).map(\.id))
        #expect(prepared.count == 200)
        #expect(prepared.first?.id == "1990")
        model.query = "Title 0"
        #expect(await model.prepareVisible(mode: .manga).map(\.id) == ["0"])
        model.items = []
        #expect(await model.prepareVisible(mode: .manga).isEmpty)
    }

    @Test func preparedChaptersKeepReleaseSelectionAndDeterministicOrder() async throws {
        let chapters = [
            Chapter(id: "a", title: "Chapter 1", number: 1, scanlator: "A", completed: false, downloaded: false),
            Chapter(id: "b", title: "Chapter 1", number: 1, scanlator: "B", completed: false, downloaded: false),
            Chapter(id: "c", title: "Chapter 2", number: 2, scanlator: "B", completed: false, downloaded: false),
        ]
        var preferences = ChapterDisplayPreferences()
        preferences.included = ["B"]
        let data = try JSONEncoder().encode(["title": preferences])
        let result = await ChapterPresentation.filtered(chapters, preferences: data, mediaID: "title", query: "", ascending: false)
        #expect(result.map(\.id) == ["c", "b"])
        let filtered = await ChapterPresentation.filtered(chapters, preferences: data, mediaID: "title", query: "1", ascending: true)
        #expect(filtered.map(\.id) == ["b"])
    }

    @Test func sourceDatesAreParsedOnceIncludingFractionalSeconds() throws {
        for value in ["2026-09-22T12:00:00Z", "2026-09-22T12:00:00.123Z"] {
            let chapter = RecentChapter(id: "one", title: nil, number: 1, uploadedAt: value,
                                        completed: false, downloaded: false)
            #expect(chapter.date != nil)
            let json = "{\"id\":\"one\",\"uploadedAt\":\"\(value)\",\"completed\":false,\"downloaded\":false}"
            let decoded = try JSONDecoder().decode(RecentChapter.self, from: Data(json.utf8))
            #expect(decoded.date == chapter.date)
        }
        #expect(RecentChapter(id: "one", title: nil, number: nil, uploadedAt: "invalid", completed: false, downloaded: false).date == nil)
    }

    @Test func historyGroupingPreservesChapterNamesAndLatestVisit() {
        let entry = HomeEntry(id: "title", title: "Title", chapters: [HomeChapter(id: "chapter", title: "Named chapter")])
        let latest = HomeSession(entryID: entry.id, chapterID: "chapter", page: 20, endedAt: .now, minutes: 2, completedUnits: 0)
        let earlier = HomeSession(entryID: entry.id, chapterID: "chapter", page: 10, endedAt: .now.addingTimeInterval(-100), minutes: 1, completedUnits: 0)
        let title = RecentHistoryTitle(entry: entry, sessions: [latest, earlier])
        #expect(title.chapters.count == 1)
        #expect(title.chapters[0].title == "Named chapter")
        #expect(title.chapters[0].page == 20)
        #expect(title.chapters[0].minutes == 3)
        #expect(RecentHistoryDay.group([title]).first?.titles.first?.id == entry.id)
    }
}

private final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    var value: Bool { lock.withLock { changed } }
    func set() { lock.withLock { changed = true } }
}

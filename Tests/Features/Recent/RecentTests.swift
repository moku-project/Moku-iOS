import Foundation
import Testing

@testable import Moku

@MainActor struct RecentTests {
    private let manga = MediaEntry(
        id: "a", title: "Alpha", media: .manga, sourceName: "Fixture", coverURL: nil)
    private func chapter(_ id: String, downloaded: Bool = false) -> RecentChapter {
        RecentChapter(
            id: id, title: "Chapter \(id)", number: Double(id),
            uploadedAt: "2026-09-20T12:00:00Z", completed: false, downloaded: downloaded)
    }

    @Test func historyCollapsesTitlesAndChaptersAndSortsUnorderedSessions() {
        let entry = HomeEntry(
            id: "a", title: "Alpha",
            chapters: [
                HomeChapter(id: "1", title: "Arrival"), HomeChapter(id: "2", title: "Departure"),
            ])
        let dates = [
            Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 300),
            Date(timeIntervalSince1970: 200),
        ]
        let sessions = dates.enumerated().map { index, date in
            HomeSession(
                entryID: "a", chapterID: index == 1 ? "2" : "1", page: index + 2,
                endedAt: date, minutes: 5, completedUnits: 0)
        }
        let snapshot = HomeSnapshot(entries: [entry], sessions: sessions)
        let titles = RecentViewModel.history(snapshot, query: "", mode: .all)
        #expect(titles.count == 1)
        #expect(titles[0].latest.chapterID == "2")
        #expect(titles[0].chapters.count == 2)
        #expect(titles[0].chapters[1].sessions.count == 2)
        #expect(titles[0].chapters[1].page == 4)
        #expect(titles[0].minutes == 15)
        #expect(
            RecentViewModel.history(snapshot, query: " arrival ", mode: .manga)[0].chapters.count
                == 1)
        #expect(RecentViewModel.history(snapshot, query: "", mode: .anime).isEmpty)
    }

    @Test func titleClearPersistsWithoutRemovingOtherActivityOrPins() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "home.json")
        let store = HomeStore(fileURL: url)
        for id in ["a", "b"] {
            let entry = HomeEntry(id: id, title: id)
            store.record(
                HomeSession(
                    entryID: id, chapterID: "1", page: 4, endedAt: .now,
                    minutes: 5, completedUnits: 1), entry: entry)
            store.pin(entry, slot: id == "a" ? 1 : 2)
        }
        await store.clearHistory(entryID: "a")
        let reloaded = HomeStore(fileURL: url)
        await reloaded.load()
        #expect(reloaded.snapshot.sessions.map(\.entryID) == ["b"])
        #expect(reloaded.snapshot.entries.count == 2)
        #expect(reloaded.snapshot.pins[1] == "a")
        await reloaded.clearHistory()
        #expect(reloaded.snapshot.sessions.isEmpty)
    }

    @Test func updateRefreshCountsNewChaptersAndDownloadActionsUseBackend() async {
        let repository = RecentTestRepository(
            before: [chapter("1")], after: [chapter("1"), chapter("2")])
        let model = RecentViewModel(repository: repository)
        #expect(await model.load(entries: [manga], refresh: true))
        #expect(model.done == 1 && model.total == 1)
        #expect(model.notice?.contains("1 new") == true)
        #expect(model.visibleUpdates(query: "2", mode: .manga).count == 1)
        #expect(model.visibleUpdates(query: "", mode: .anime).isEmpty)
        await model.act(on: model.updates[0], delete: false)
        #expect(model.queued.contains(model.updates[0].id))
        await model.act(on: model.updates[0], delete: true)
        #expect(model.queued.isEmpty)
        #expect(await repository.actions == [false, true])
    }

    @Test func failurePreservesExistingRowsAndOnlyLoadsRequestedProfileEntries() async {
        let repository = RecentTestRepository(before: [chapter("1")], after: [])
        let model = RecentViewModel(repository: repository)
        #expect(await model.load(entries: [manga]))
        await repository.fail()
        #expect(!(await model.load(entries: [manga], refresh: true)))
        #expect(model.updates.count == 1)
        #expect(model.failedTitles == ["Alpha"])
        #expect(model.error != nil)
        #expect(await model.load(entries: []))
        #expect(model.updates.isEmpty)
        #expect(await repository.requested.allSatisfy { $0 == "a" })
    }

    @Test func activitySplitsChaptersAndExcludesPausedTime() {
        let store = HomeStore(fileURL: nil)
        let recorder = ActivityRecorder()
        let entry = HomeEntry(id: "a", title: "Alpha")
        func sample(_ chapter: String, _ seconds: Double, active: Bool = true) {
            recorder.sample(
                home: store, entry: entry, chapterID: chapter, position: 8,
                completed: true, active: active, valid: true,
                now: Date(timeIntervalSince1970: seconds))
        }
        sample("1", 0)
        sample("1", 65, active: false)
        sample("1", 200)
        sample("2", 210)
        sample("2", 275, active: false)
        recorder.stop(home: store, now: Date(timeIntervalSince1970: 400))
        #expect(store.snapshot.sessions.count == 2)
        #expect(store.snapshot.sessions.allSatisfy { $0.minutes == 1 })
        #expect(store.snapshot.sessions.allSatisfy { $0.completedUnits == 1 })
    }
}

private actor RecentTestRepository: RecentRepository {
    let before: [RecentChapter]
    let after: [RecentChapter]
    var failing = false
    var actions: [Bool] = []
    var requested: [String] = []
    init(before: [RecentChapter], after: [RecentChapter]) {
        self.before = before
        self.after = after
    }
    func fail() { failing = true }
    func chapters(for entry: MediaEntry, refresh: Bool) throws -> [RecentUpdate] {
        requested.append(entry.id)
        if failing { throw SearchFailure.notConnected }
        return (refresh ? after : before).map {
            RecentUpdate(entry: entry, mediaID: entry.id, chapter: $0)
        }
    }
    func entry(id: String) throws -> MediaEntry { throw SearchFailure.notConnected }
    func download(_ update: RecentUpdate, delete: Bool) { actions.append(delete) }
}

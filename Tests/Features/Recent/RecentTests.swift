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

    @Test func historyGroupsTitlesNewestFirstAndFilters() {
        func session(_ id: String, _ media: String, at seconds: Double, chapter: String) -> HistorySession {
            HistorySession(
                id: id, mediaID: media, title: media == "a" ? "Alpha" : "Beta", media: media == "a" ? .manga : .anime,
                endChapterID: chapter, endChapterTitle: chapter, startedAt: Date(timeIntervalSince1970: seconds - 60),
                endedAt: Date(timeIntervalSince1970: seconds), durationMs: 300_000)
        }
        let sessions = [
            session("1", "a", at: 100, chapter: "Arrival"), session("2", "b", at: 300, chapter: "Episode 2"),
            session("3", "a", at: 200, chapter: "Departure"),
        ]
        let titles = RecentViewModel.history(sessions, entries: [:], query: "", mode: .all)
        #expect(titles.map(\.id) == ["b", "a"])
        #expect(titles[1].latest.id == "3")
        #expect(titles[1].minutes == 10)
        #expect(RecentViewModel.history(sessions, entries: [:], query: " arrival ", mode: .all).map(\.id) == ["a"])
        #expect(RecentViewModel.history(sessions, entries: [:], query: "", mode: .anime).map(\.id) == ["b"])
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

import Foundation
import Testing

@testable import Moku

@MainActor
struct HomeStoreTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12))!
    }

    private func session(_ entry: String, day: Int, units: Int = 2) -> HomeSession {
        HomeSession(
            entryID: entry, chapterID: "one", page: 12, endedAt: date(day), minutes: 15,
            completedUnits: units)
    }

    @Test func emptyHomeHasNoInventedActivity() {
        let store = HomeStore(fileURL: nil)
        #expect(store.recentSessions.isEmpty)
        let stats = store.statistics(now: date(19), calendar: calendar)
        #expect(stats.units == 0 && stats.currentStreak == 0 && stats.bestStreak == 0)
        #expect(stats.firstRead == nil && stats.daily.isEmpty)
    }

    @Test func recentTitlesAreDeduplicatedNewestFirst() {
        let store = HomeStore(fileURL: nil)
        let a = HomeEntry(id: "a", title: "A")
        let b = HomeEntry(id: "b", title: "B")
        store.record(session("a", day: 17), entry: a)
        store.record(session("b", day: 18), entry: b)
        store.record(session("a", day: 19), entry: a)
        #expect(store.recentSessions.map(\.entryID) == ["a", "b"])
    }

    @Test func statsUseCalendarDaysAndDoNotCountRepeatedSessionUpdates() {
        let store = HomeStore(fileURL: nil)
        let entry = HomeEntry(id: "a", title: "A")
        var latest = session("a", day: 18)
        store.record(session("a", day: 15), entry: entry)
        store.record(session("a", day: 17), entry: entry)
        store.record(latest, entry: entry)
        latest.completedUnits = 4
        store.record(latest, entry: entry)
        let stats = store.statistics(now: date(19), calendar: calendar)
        #expect(stats.units == 1 && stats.thisWeek == 8)
        #expect(stats.minutes == 45 && stats.series == 1)
        #expect(stats.currentStreak == 2 && stats.bestStreak == 2)
        #expect(stats.perDay == 0.25)
        #expect(store.statistics(now: date(20), calendar: calendar).currentStreak == 0)
        #expect(store.statistics(now: date(20), calendar: calendar).bestStreak == 2)
    }

    @Test func historySurvivesReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "home.json")
        let store = HomeStore(fileURL: url)
        let entry = HomeEntry(id: "a", title: "A")
        store.record(session("a", day: 19), entry: entry)
        await store.flush()
        let restored = HomeStore(fileURL: url)
        await restored.load()
        #expect(restored.recentSessions.first.flatMap { restored.entry($0.entryID) }?.title == "A")
        #expect(restored.snapshot.sessions.count == 1)
    }

    @Test func editsDuringLoadingPreserveExistingHistory() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let first = HomeEntry(id: "a", title: "A")
        let second = HomeEntry(id: "b", title: "B")
        let saved = HomeSnapshot(entries: [first], sessions: [session("a", day: 18)])
        try JSONEncoder().encode(saved).write(to: url)
        let store = HomeStore(fileURL: url)
        store.record(session("b", day: 19), entry: second)
        await store.flush()
        let restored = HomeStore(fileURL: url)
        await restored.load()
        #expect(restored.snapshot.sessions.count == 2)
        #expect(restored.recentSessions.first?.entryID == "b")
    }

    @Test func savedSnapshotsWithPinsStillLoad() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = #"{"entries":[{"id":"a","title":"A","media":"Manga","genres":[],"unreadCount":0,"chapters":[]}],"sessions":[],"pins":{"1":"a"}}"#
        try Data(legacy.utf8).write(to: url)
        let restored = HomeStore(fileURL: url)
        await restored.load()
        #expect(restored.storageError == nil)
        #expect(restored.entry("a")?.title == "A")
    }

    @Test func recordingKeepsResolvedSourceAndMetadata() {
        let store = HomeStore(fileURL: nil)
        let media = MediaEntry(id: "a", title: "A", media: .manga, sourceName: "Source", coverURL: nil)
        var entry = HomeEntry(media)
        entry.author = "Author"
        entry.summary = "Description"
        store.updateEntry(entry)
        store.record(session("a", day: 19), entry: HomeEntry(id: "a", title: "A"))
        #expect(store.entry("a")?.sourceEntry == media)
        #expect(store.entry("a")?.summary == "Description")
    }

    @Test func readingVisitsContributeToStreakHeatmapAndWeeklyCounts() {
        let store = HomeStore(fileURL: nil)
        store.record(session("a", day: 19, units: 0), entry: HomeEntry(id: "a", title: "A"))
        let stats = store.statistics(now: date(19), calendar: calendar)
        #expect(stats.currentStreak == 1)
        #expect(stats.units == 1)
        #expect(stats.daily.values.reduce(0, +) == 1)
        #expect(stats.thisWeek == 1)
    }

    @Test func shortSessionsContributeToTotalReadingTime() {
        let store = HomeStore(fileURL: nil)
        var first = session("a", day: 19, units: 0)
        first.minutes = 0
        first.durationSeconds = 40
        var second = first
        second.id = UUID()
        second.chapterID = "two"
        store.record(first, entry: HomeEntry(id: "a", title: "A"))
        store.record(second, entry: HomeEntry(id: "a", title: "A"))
        let stats = store.statistics(now: date(19), calendar: calendar)
        #expect(stats.minutes == 1)
        #expect(stats.units == 2)
    }

    @Test func corruptHistoryIsPreserved() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("unreadable".utf8)
        try original.write(to: url)
        let store = HomeStore(fileURL: url)
        await store.load()
        #expect(store.storageError != nil)
        store.record(session("a", day: 19), entry: HomeEntry(id: "a", title: "A"))
        await store.flush()
        #expect(try Data(contentsOf: url) == original)
    }
}

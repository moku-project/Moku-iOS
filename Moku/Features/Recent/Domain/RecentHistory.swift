import Foundation

struct RecentHistoryTitle: Identifiable, Sendable {
    let entry: HomeEntry
    let sessions: [HomeSession]
    var id: String { entry.id }
    var latest: HomeSession { sessions[0] }
    var minutes: Int { sessions.reduce(0) { $0 + max(0, $1.minutes) } }
    let chapters: [RecentHistoryChapter]
    init(entry: HomeEntry, sessions: [HomeSession]) {
        self.entry = entry
        self.sessions = sessions
        let names = Dictionary(entry.chapters.map { ($0.id, $0.title) }, uniquingKeysWith: { _, last in last })
        chapters = Dictionary(grouping: sessions, by: \.chapterID).map { id, values in
            RecentHistoryChapter(id: id, title: names[id] ?? "Chapter",
                                 sessions: values.sorted { $0.endedAt > $1.endedAt })
        }.sorted { $0.latest.endedAt > $1.latest.endedAt }
    }
}

struct RecentHistoryChapter: Identifiable, Sendable {
    let id: String
    let title: String
    let sessions: [HomeSession]
    var latest: HomeSession { sessions[0] }
    var page: Int { sessions.map(\.page).max() ?? 0 }
    var minutes: Int { sessions.reduce(0) { $0 + max(0, $1.minutes) } }
}

struct RecentHistoryDay: Identifiable, Sendable {
    let id: Date
    let titles: [RecentHistoryTitle]
    static func group(_ titles: [RecentHistoryTitle], calendar: Calendar = .current) -> [Self] {
        Dictionary(grouping: titles) { calendar.startOfDay(for: $0.latest.endedAt) }
            .map { Self(id: $0.key, titles: $0.value) }.sorted { $0.id > $1.id }
    }
}

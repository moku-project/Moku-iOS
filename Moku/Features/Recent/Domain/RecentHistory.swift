import Foundation

struct RecentHistoryTitle: Identifiable {
    let entry: HomeEntry
    let sessions: [HomeSession]
    var id: String { entry.id }
    var latest: HomeSession { sessions[0] }
    var minutes: Int { sessions.reduce(0) { $0 + max(0, $1.minutes) } }
    var chapters: [RecentHistoryChapter] {
        Dictionary(grouping: sessions, by: \.chapterID).map { id, values in
            RecentHistoryChapter(
                id: id,
                title: entry.chapters.first { $0.id == id }?.title ?? "Chapter",
                sessions: values.sorted { $0.endedAt > $1.endedAt })
        }.sorted { $0.latest.endedAt > $1.latest.endedAt }
    }
}

struct RecentHistoryChapter: Identifiable {
    let id: String
    let title: String
    let sessions: [HomeSession]
    var latest: HomeSession { sessions[0] }
    var page: Int { sessions.map(\.page).max() ?? 0 }
    var minutes: Int { sessions.reduce(0) { $0 + max(0, $1.minutes) } }
}

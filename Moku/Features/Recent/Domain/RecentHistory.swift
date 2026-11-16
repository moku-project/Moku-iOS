import Foundation

struct RecentHistoryTitle: Identifiable, Sendable {
    let entry: HomeEntry
    /// Newest first.
    let sessions: [HistorySession]
    var id: String { entry.id }
    var latest: HistorySession { sessions[0] }
    var minutes: Int { sessions.reduce(0) { $0 + $1.minutes } }
}

struct RecentHistoryDay: Identifiable, Sendable {
    let id: Date
    let titles: [RecentHistoryTitle]
    static func group(_ titles: [RecentHistoryTitle], calendar: Calendar = .current) -> [Self] {
        Dictionary(grouping: titles) { calendar.startOfDay(for: $0.latest.endedAt) }
            .map { Self(id: $0.key, titles: $0.value) }.sorted { $0.id > $1.id }
    }
}

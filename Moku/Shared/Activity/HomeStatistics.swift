import Foundation

struct HomeSlot: Identifiable {
    var id: Int
    var entry: HomeEntry?
    var session: HomeSession?
    var isPinned = false
}

struct HomeStatistics: Sendable {
    var units = 0
    var minutes = 0
    var thisWeek = 0
    var series = 0
    var currentStreak = 0
    var bestStreak = 0
    var firstRead: Date?
    var lastRead: Date?
    var perDay = 0.0
    var byMedia: [String: Int] = [:]
    var daily: [Date: Int] = [:]
}

extension HomeStatistics {
    nonisolated static func calculate(snapshot: HomeSnapshot, now: Date = .now, calendar: Calendar = .current) -> HomeStatistics {
        var result = HomeStatistics()
        let sessions = snapshot.sessions.filter { $0.endedAt <= now }
        let today = calendar.startOfDay(for: now)
        let weekStart = now.addingTimeInterval(-7 * 86_400)
        let mediaByID = Dictionary(
            snapshot.entries.map { ($0.id, $0.media) }, uniquingKeysWith: { _, latest in latest })
        result.units = Set(sessions.map { [$0.entryID, $0.chapterID] }).count
        var seconds = 0.0
        for session in sessions {
            // Desktop activity includes chapters visited without reaching the end.
            let units = max(1, session.completedUnits)
            seconds += min(3600, max(0, session.durationSeconds ?? Double(session.minutes) * 60))
            if session.endedAt >= weekStart { result.thisWeek += units }
            let day = calendar.startOfDay(for: session.endedAt)
            result.daily[day, default: 0] += units
            if let media = mediaByID[session.entryID] { result.byMedia[media, default: 0] += units }
        }
        result.minutes = Int((seconds / 60).rounded())
        result.series = Set(sessions.map(\.entryID)).count
        result.firstRead = sessions.map { $0.startedAt ?? $0.endedAt }.min()
        result.lastRead = sessions.map(\.endedAt).max()
        if let first = result.firstRead {
            let days = max(1, Int(ceil(now.timeIntervalSince(first) / 86_400)))
            result.perDay = Double(result.units) / Double(days)
        }
        var previous: Date?
        var streak = 0
        for day in result.daily.keys.sorted() {
            streak =
                previous.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day
                ? streak + 1 : 1
            result.bestStreak = max(result.bestStreak, streak)
            previous = day
        }
        if let previous, previous >= calendar.date(byAdding: .day, value: -1, to: today)! {
            result.currentStreak = streak
        }
        return result
    }
}

import Foundation

enum RecentFormat {
    /// Matches desktop Moku's timeAgo: one unit, then a short date after a week.
    static func timeAgo(_ date: Date, now: Date = .now) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(date)) / 60)
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func duration(_ minutes: Int) -> String {
        minutes < 1
            ? "< 1 min" : minutes < 60 ? "\(minutes) min" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

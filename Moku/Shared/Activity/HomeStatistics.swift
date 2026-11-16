import Foundation

struct HomeStatistics: Equatable, Sendable {
    var units = 0
    var minutes = 0
    var thisWeek = 0
    var series = 0
    var currentStreak = 0
    var bestStreak = 0
    var firstRead: Date?
    var lastRead: Date?
    var perDay = 0.0
    /// Chapters per local day, keyed by the start of that day.
    var daily: [Date: Int] = [:]
}

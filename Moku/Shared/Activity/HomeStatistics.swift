import Foundation

struct HomeSlot: Identifiable {
    var id: Int
    var entry: HomeEntry?
    var session: HomeSession?
    var isPinned = false
}

struct HomeStatistics {
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

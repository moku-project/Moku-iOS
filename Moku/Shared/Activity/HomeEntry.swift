import Foundation

struct HomeChapter: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var page: Int = 1
    var isRead = false
}

struct HomeEntry: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var coverURL: URL?
    var media: String = "Manga"
    var genres: [String] = []
    var unreadCount = 0
    var chapters: [HomeChapter] = []
}

struct HomeSession: Codable, Identifiable, Sendable {
    var id = UUID()
    var entryID: String
    var chapterID: String
    var page: Int
    var endedAt: Date
    var minutes: Int
    var completedUnits: Int
}

struct HomeSnapshot: Codable, Sendable {
    var entries: [HomeEntry] = []
    var sessions: [HomeSession] = []
    var pins: [Int: String] = [:]
}

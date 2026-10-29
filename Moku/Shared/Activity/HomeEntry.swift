import Foundation

struct HomeChapter: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var page: Int = 1
    var isRead = false
    var uploadedAt: String? = nil

    var displayTitle: String {
        title.replacingOccurrences(of: #"^Chapter\s+(?=\d)"#, with: "Ch.", options: .regularExpression)
            .replacingOccurrences(of: #"^Episode\s+(?=\d)"#, with: "Ep.", options: .regularExpression)
    }
}

struct HomeEntry: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var coverURL: URL?
    var media: String = "Manga"
    var genres: [String] = []
    var unreadCount = 0
    var chapters: [HomeChapter] = []
    var sourceEntry: MediaEntry? = nil
    var author: String? = nil
    var summary: String? = nil
}

struct HomeSession: Codable, Identifiable, Sendable {
    var id = UUID()
    var entryID: String
    var chapterID: String
    var page: Int
    var endedAt: Date
    var minutes: Int
    var completedUnits: Int
    var startedAt: Date? = nil
    var durationSeconds: Double? = nil
}

struct HomeSnapshot: Codable, Sendable {
    var entries: [HomeEntry] = []
    var sessions: [HomeSession] = []
    var pins: [Int: String] = [:]
}

extension HomeEntry {
    init(_ entry: MediaEntry) {
        self.init(id: entry.id, title: entry.title, coverURL: entry.coverURL,
                  media: entry.media.title, sourceEntry: entry)
    }
}

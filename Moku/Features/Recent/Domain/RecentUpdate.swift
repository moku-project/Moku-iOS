import Foundation

struct RecentChapter: Decodable, Sendable, Identifiable {
    let id: String
    let title: String?
    let number: Double?
    let uploadedAt: String?
    let completed: Bool
    var downloaded: Bool
    var label: String { title ?? number.map { "Chapter \($0.formatted())" } ?? "Chapter" }
    var date: Date? {
        guard let uploadedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: uploadedAt) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: uploadedAt)
    }
}

struct RecentUpdate: Identifiable, Sendable {
    let entry: MediaEntry
    let mediaID: String
    var chapter: RecentChapter
    var id: String { mediaID + ":" + chapter.id }
}

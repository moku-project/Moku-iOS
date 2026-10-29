import Foundation

struct RecentChapter: Decodable, Sendable, Identifiable {
    let id: String
    let title: String?
    let number: Double?
    let uploadedAt: String?
    let completed: Bool
    var downloaded: Bool
    var label: String { title ?? number.map { "Chapter \($0.formatted())" } ?? "Chapter" }
    let date: Date?

    init(id: String, title: String?, number: Double?, uploadedAt: String?, completed: Bool, downloaded: Bool) {
        self.id = id; self.title = title; self.number = number; self.uploadedAt = uploadedAt
        self.completed = completed; self.downloaded = downloaded
        date = uploadedAt.flatMap {
            (try? Date.ISO8601FormatStyle().parse($0))
                ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0))
        }
    }

    private enum CodingKeys: String, CodingKey { case id, title, number, uploadedAt, completed, downloaded }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(String.self, forKey: .id),
                  title: try values.decodeIfPresent(String.self, forKey: .title),
                  number: try values.decodeIfPresent(Double.self, forKey: .number),
                  uploadedAt: try values.decodeIfPresent(String.self, forKey: .uploadedAt),
                  completed: try values.decode(Bool.self, forKey: .completed),
                  downloaded: try values.decode(Bool.self, forKey: .downloaded))
    }
}

struct RecentUpdate: Identifiable, Sendable {
    let entry: MediaEntry
    let mediaID: String
    var chapter: RecentChapter
    var id: String { mediaID + ":" + chapter.id }
}

import Foundation

struct TrackingDraft: Codable, Sendable {
    let media: ContentMode
    let statuses: Set<String>
    let sourceID: String?
    let trackerKey: String
    let items: [TrackingImportItem]
    let username: String?
}

actor TrackingDraftStore {
    let url: URL
    init(url: URL) { self.url = url }

    func read() throws -> TrackingDraft? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(TrackingDraft.self, from: Data(contentsOf: url))
    }

    func write(_ draft: TrackingDraft) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: url, options: [.atomic, .completeFileProtection])
    }
}

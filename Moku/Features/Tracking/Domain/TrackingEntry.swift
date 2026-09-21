import Foundation

struct TrackingRemoteEntry: Codable, Sendable, Identifiable {
    let remoteId: String
    let title: String
    let titleRomaji: String?
    let titleEnglish: String?
    let status: String
    let progress: Double
    let score: Double
    let coverUrl: String?
    var id: String { remoteId }
    var names: [String] { [title, titleRomaji, titleEnglish].compactMap { $0 } }
}

struct TrackingImportItem: Codable, Identifiable, Sendable {
    var remote: TrackingRemoteEntry
    var match: MediaEntry?
    var state: State = .pending
    var message: String?
    var id: String { remote.id }
    enum State: String, Codable {
        case pending, matched, unmatched, skipped, imported, failed, existing
    }
}

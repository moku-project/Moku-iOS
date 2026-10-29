import Foundation

protocol RecentRepository: Sendable {
    func chapters(for entry: MediaEntry, refresh: Bool) async throws -> [RecentUpdate]
    func entry(id: String) async throws -> MediaEntry
    func download(_ update: RecentUpdate, delete: Bool) async throws
    /// Desktop Recent › Updates: chapters the server found during library updates.
    /// `nil` means this repository has no server feed (previews).
    func serverFeed() async throws -> [RecentUpdate]?
    var hasServerFeed: Bool { get }
    func startLibraryUpdate() async throws
    func libraryUpdateStatus() async throws -> LibraryUpdateStatus
}

struct LibraryUpdateStatus: Decodable, Sendable {
    let running: Bool
    let total: Int
    let done: Int
    let currentTitle: String?
    let newChapterCount: Int
    let failedTitles: [String]
}

extension RecentRepository {
    var hasServerFeed: Bool { false }
    func serverFeed() async throws -> [RecentUpdate]? { nil }
    func startLibraryUpdate() async throws {}
    func libraryUpdateStatus() async throws -> LibraryUpdateStatus {
        LibraryUpdateStatus(running: false, total: 0, done: 0, currentTitle: nil, newChapterCount: 0, failedTitles: [])
    }
}

import Foundation

protocol TrackingRepository: Sendable {
    func services() async throws -> [TrackingService]
    func login(key: String, token: String) async throws
    func logout(key: String) async throws
    func list(key: String, media: ContentMode, statuses: Set<String>) async throws
        -> [TrackingRemoteEntry]
    func importTitle(_ item: TrackingImportItem, key: String, media: ContentMode) async throws
        -> MediaEntry
    func linkedIDs(key: String, entries: [MediaEntry]) async throws -> Set<String>
}

extension TrackingRepository {
    func linkedIDs(key: String, entries: [MediaEntry]) async throws -> Set<String> { [] }
}

import Foundation

protocol DetailsRepository: Sendable {
    func metadata(for entry: MediaEntry, refresh: Bool) async throws -> MediaDetails
    func chapters(mediaID: String) async throws -> [Chapter]
    func chapters(mediaID: String, refresh: Bool) async throws -> [Chapter]
}

extension DetailsRepository {
    func chapters(mediaID: String, refresh: Bool) async throws -> [Chapter] {
        try await chapters(mediaID: mediaID)
    }
}

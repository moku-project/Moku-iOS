import Foundation

protocol DetailsRepository: Sendable {
    func metadata(for entry: MediaEntry, refresh: Bool) async throws -> MediaDetails
    func chapters(mediaID: String) async throws -> [Chapter]
}

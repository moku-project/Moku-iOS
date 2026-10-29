import Foundation

protocol PlayerRepository: Sendable {
    func stream(chapterID: String) async throws -> (EpisodeStream, Double)
    func request(path: String) async throws -> URLRequest
    func subtitle(path: String) async throws -> String
    func save(mediaID: String, chapterID: String, position: Double, duration: Double) async throws
    /// Intro/outro/recap ranges (AniSkip and source markers), once the length is known.
    func skipMarkers(chapterID: String, lengthMs: Int) async throws -> [SkipMarker]
}

extension PlayerRepository {
    func skipMarkers(chapterID: String, lengthMs: Int) async throws -> [SkipMarker] { [] }
}

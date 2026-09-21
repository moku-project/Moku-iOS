import Foundation

protocol PlayerRepository: Sendable {
    func stream(chapterID: String) async throws -> (EpisodeStream, Double)
    func request(path: String) async throws -> URLRequest
    func subtitle(path: String) async throws -> String
    func save(mediaID: String, chapterID: String, position: Double, duration: Double) async throws
}

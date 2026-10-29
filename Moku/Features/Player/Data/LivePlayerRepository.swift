import Foundation

struct LivePlayerRepository: PlayerRepository {
    func stream(chapterID: String) async throws -> (EpisodeStream, Double) {
        struct Response: Decodable, Sendable {
            struct Chapter: Decodable, Sendable {
                struct Progress: Decodable, Sendable { let positionSeconds: Double? }
                let videoStream: EpisodeStream?
                let readingProgress: Progress?
            }
            let chapter: Chapter?
        }
        let response: Response = try await BackendAPI.shared.graphql(
            """
            { chapter(id: \(BackendAPI.literal(chapterID))) {
                videoStream { url sources { label url } subtitles { lang url } }
                readingProgress { positionSeconds }
            } }
            """)
        guard let stream = response.chapter?.videoStream else {
            throw EmbeddedSearchError.message("No playable video is available for this episode.")
        }
        return (stream, response.chapter?.readingProgress?.positionSeconds ?? 0)
    }

    func request(path: String) async throws -> URLRequest {
        let connection = try await Backend.shared.connection()
        return try connection.contentRequest(path: path)
    }

    func subtitle(path: String) async throws -> String {
        let request = try await request(path: path)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
            let text = String(data: data, encoding: .utf8)
        else { throw EmbeddedSearchError.message("Couldn’t load subtitles.") }
        return text
    }

    func save(mediaID: String, chapterID: String, position: Double, duration: Double) async throws {
        guard duration.isFinite, duration > 0, position.isFinite else { return }
        struct Response: Decodable, Sendable {
            struct Progress: Decodable, Sendable { let progress: Double }
            let updateReadingProgress: Progress
        }
        let progress = min(1, max(0, position / duration))
        let _: Response = try await BackendAPI.shared.graphql(
            """
            mutation { updateReadingProgress(mediaId: \(BackendAPI.literal(mediaID)),
                chapterId: \(BackendAPI.literal(chapterID)), progress: \(progress),
                completed: \(progress >= 0.9), positionSeconds: \(position),
                durationSeconds: \(duration)) { progress } }
            """)
    }

    func skipMarkers(chapterID: String, lengthMs: Int) async throws -> [SkipMarker] {
        struct Response: Decodable, Sendable { let skipTimestamps: [SkipMarker] }
        let response: Response = try await BackendAPI.shared.graphql(
            "{ skipTimestamps(chapterId: \(BackendAPI.literal(chapterID)), episodeLengthMs: \(lengthMs)) { type name startMs endMs } }",
            cacheFor: 3600, requiresSourceRuntime: false)
        return response.skipTimestamps.filter { $0.endMs > $0.startMs }
    }
}

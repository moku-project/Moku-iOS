import Foundation

struct LiveRecentRepository: RecentRepository {
    func chapters(for entry: MediaEntry, refresh: Bool) async throws -> [RecentUpdate] {
        let mediaID: String
        if Int64(entry.id) != nil { mediaID = entry.id }
        else { mediaID = try await LiveMediaRepository.shared.metadata(for: entry, refresh: false).id }
        if refresh { _ = try await LiveMediaRepository.shared.chapters(mediaID: mediaID, refresh: true) }
        struct Response: Decodable, Sendable {
            struct Media: Decodable, Sendable { let chapters: [RecentChapter] }
            let media: Media?
        }
        let result: Response = try await BackendAPI.shared.graphql(
            """
            { media(id: \(BackendAPI.literal(mediaID))) {
                chapters { id title number uploadedAt completed downloaded }
            } }
            """, requiresSourceRuntime: false)
        guard let media = result.media else { throw SearchFailure.notConnected }
        return media.chapters.map { RecentUpdate(entry: entry, mediaID: mediaID, chapter: $0) }
    }

    func entry(id: String) async throws -> MediaEntry {
        struct Response: Decodable, Sendable {
            struct Media: Decodable, Sendable {
                let id: String
                let title: String
                let contentType: String
                let sourceName: String
                let thumbnailUrl: String?
                let extensionId: String?
                let externalId: String
            }
            let media: Media?
        }
        let result: Response = try await BackendAPI.shared.graphql(
            """
            { media(id: \(BackendAPI.literal(id))) {
                id title contentType sourceName thumbnailUrl extensionId externalId
            } }
            """)
        guard let media = result.media else { throw SearchFailure.notConnected }
        return MediaEntry(
            id: media.id, title: media.title,
            media: media.contentType == "ANIME"
                ? .anime : media.contentType == "NOVEL" ? .novels : .manga,
            sourceName: media.sourceName, coverURL: BackendAPI.coverURL(media.thumbnailUrl),
            extensionID: media.extensionId, externalID: media.externalId)
    }

    func download(_ update: RecentUpdate, delete: Bool) async throws {
        if delete {
            struct Response: Decodable, Sendable { let deleteDownload: Bool }
            let result: Response = try await BackendAPI.shared.graphql(
                """
                mutation { deleteDownload(mediaId: \(BackendAPI.literal(update.mediaID)),
                    chapterIds: [\(BackendAPI.literal(update.chapter.id))]) }
                """)
            guard result.deleteDownload else { throw SearchFailure.notConnected }
        } else {
            try await LiveReaderRepository().download(
                mediaID: update.mediaID, chapterIDs: [update.chapter.id])
        }
    }
}

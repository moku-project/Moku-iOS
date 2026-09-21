import Foundation

struct LiveReaderRepository: ReaderRepository {
    func opened(mediaID: String, chapterID: String) async throws {
        try await BackendAPI.shared.chapterOpened(mediaID: mediaID, chapterID: chapterID)
    }
    func pages(chapterID: String) async throws -> [String] {
        struct Response: Decodable, Sendable {
            struct Chapter: Decodable, Sendable { let pages: [String] }
            let chapter: Chapter?
        }
        let result: Response = try await BackendAPI.shared.graphql(
            "{chapter(id: \(BackendAPI.literal(chapterID))){pages}}", cacheFor: 60)
        guard let pages = result.chapter?.pages, !pages.isEmpty else {
            throw EmbeddedSearchError.message("This chapter has no pages.")
        }
        return pages
    }
    func image(path: String) async throws -> Data {
        try await BackendAPI.shared.readerPageData(path: path)
    }
    func progress(mediaID: String, chapterID: String, value: Double, completed: Bool) async throws {
        struct Response: Decodable, Sendable {
            struct Progress: Decodable, Sendable { let progress: Double }
            let updateReadingProgress: Progress
        }
        let _: Response = try await BackendAPI.shared.graphql(
            """
            mutation { updateReadingProgress(mediaId: \(BackendAPI.literal(mediaID)),
            chapterId: \(BackendAPI.literal(chapterID)), progress: \(value), completed: \(completed)) { progress } }
            """)
    }
    func download(mediaID: String, chapterIDs: [String]) async throws {
        struct Response: Decodable, Sendable {
            struct Download: Decodable, Sendable { let chapterId: String }
            let enqueueDownload: [Download]
        }
        let ids = chapterIDs.map(BackendAPI.literal).joined(separator: ",")
        let _: Response = try await BackendAPI.shared.graphql(
            """
            mutation { enqueueDownload(mediaId: \(BackendAPI.literal(mediaID)), chapterIds: [\(ids)]) { chapterId } }
            """)
        struct Start: Decodable, Sendable { let startDownloader: Bool }
        let _: Start = try await BackendAPI.shared.graphql("mutation { startDownloader }")
    }
}

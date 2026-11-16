import Foundation

struct LiveReaderRepository: ReaderRepository {
    /// No call needed: Tsunagu runs download-ahead and delete-on-read when progress marks a chapter read.
    func opened(mediaID: String, chapterID: String) async throws {}
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
        if PDFPageSource.parse(path) != nil {
            return try await PDFPageSource.shared.image(path: path) {
                try await BackendAPI.shared.readerDocumentData(path: $0)
            }
        }
        return try await BackendAPI.shared.readerPageData(path: path)
    }
    func progress(mediaID: String, chapterID: String, value: Double, completed: Bool, page: Int?)
        async throws
    {
        struct Response: Decodable, Sendable {
            struct Progress: Decodable, Sendable { let progress: Double }
            let updateReadingProgress: Progress
        }
        let _: Response = try await BackendAPI.shared.graphql(
            """
            mutation { updateReadingProgress(mediaId: \(BackendAPI.literal(mediaID)),
            chapterId: \(BackendAPI.literal(chapterID)), progress: \(value), completed: \(completed)\(page.map { ", page: \($0)" } ?? "")) { progress } }
            """)
    }
    func chapterState(mediaID: String, chapterID: String) async throws -> ReaderChapterState? {
        try await ChapterSync.state(mediaID: mediaID, chapterID: chapterID)
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

enum ChapterSync {
    static func state(mediaID: String, chapterID: String) async throws -> ReaderChapterState? {
        struct Response: Decodable, Sendable {
            struct Chapter: Decodable, Sendable {
                struct Progress: Decodable, Sendable {
                    let progress: Double
                    let completed: Bool
                    let updatedAt: String?
                }
                let readingProgress: Progress?
            }
            struct Media: Decodable, Sendable {
                struct Point: Decodable, Sendable {
                    let chapterId: String
                    let page: Int?
                }
                let resumePoint: Point?
            }
            let chapter: Chapter?
            let media: Media?
        }
        // Never cached: another device may have moved on since the last read.
        let response: Response = try await BackendAPI.shared.graphql(
            """
            { chapter(id: \(BackendAPI.literal(chapterID))) { readingProgress { progress completed updatedAt } } \
            media(id: \(BackendAPI.literal(mediaID))) { resumePoint { chapterId page } } }
            """, requiresSourceRuntime: false)
        guard let chapter = response.chapter else { return nil }
        let point = response.media?.resumePoint
        return ReaderChapterState(
            progress: chapter.readingProgress.map {
                .init(progress: $0.progress, completed: $0.completed, updatedAt: date($0.updatedAt))
            },
            resumePage: point?.chapterId == chapterID ? point?.page : nil)
    }

    /// Go encodes times as RFC 3339 with up to nine fractional digits.
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = try? Date(value, strategy: .iso8601) { return date }
        if let date = try? Date(
            value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        {
            return date
        }
        // Trim the fraction to milliseconds, which ISO8601FormatStyle accepts.
        guard let dot = value.firstIndex(of: ".") else { return nil }
        let rest = value[value.index(after: dot)...]
        let digits = rest.prefix { $0.isNumber }
        let zone = rest.dropFirst(digits.count)
        let trimmed =
            value[..<dot] + "."
            + String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0) + zone
        return try? Date(
            String(trimmed), strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}

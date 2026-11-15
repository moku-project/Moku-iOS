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
    func chapterState(chapterID: String) async throws -> ReaderChapterState? {
        try await ChapterSync.state(chapterID: chapterID)
    }
    func setBookmarked(mediaID: String, chapterID: String, bookmarked: Bool) async throws {
        try await ChapterSync.setBookmarked(mediaID: mediaID, chapterIDs: [chapterID], bookmarked: bookmarked)
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

/// Chapter progress and bookmark calls shared by the manga and novel readers.
enum ChapterSync {
    static func state(chapterID: String) async throws -> ReaderChapterState? {
        struct Response: Decodable, Sendable {
            struct Chapter: Decodable, Sendable {
                struct Progress: Decodable, Sendable {
                    let progress: Double
                    let completed: Bool
                    let updatedAt: String?
                }
                let bookmarked: Bool?
                let readingProgress: Progress?
            }
            let chapter: Chapter?
        }
        // Never cached: another device may have moved on since the last read.
        let response: Response = try await BackendAPI.shared.graphql(
            "{ chapter(id: \(BackendAPI.literal(chapterID))) { bookmarked readingProgress { progress completed updatedAt } } }",
            requiresSourceRuntime: false)
        guard let chapter = response.chapter else { return nil }
        return ReaderChapterState(
            progress: chapter.readingProgress.map {
                .init(progress: $0.progress, completed: $0.completed, updatedAt: date($0.updatedAt))
            },
            bookmarked: chapter.bookmarked ?? false)
    }

    static func setBookmarked(mediaID: String, chapterIDs: [String], bookmarked: Bool) async throws {
        struct Response: Decodable, Sendable {
            struct Chapter: Decodable, Sendable { let id: String }
            let setChaptersBookmarked: [Chapter]
        }
        let ids = chapterIDs.map(BackendAPI.literal).joined(separator: ",")
        let _: Response = try await BackendAPI.shared.graphql(
            """
            mutation { setChaptersBookmarked(mediaId: \(BackendAPI.literal(mediaID)), chapterIds: [\(ids)], bookmarked: \(bookmarked)) { id } }
            """, requiresSourceRuntime: false)
    }

    /// Go encodes times as RFC 3339 with up to nine fractional digits.
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = try? Date(value, strategy: .iso8601) { return date }
        if let date = try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        // Trim the fraction to milliseconds, which ISO8601FormatStyle accepts.
        guard let dot = value.firstIndex(of: ".") else { return nil }
        let rest = value[value.index(after: dot)...]
        let digits = rest.prefix { $0.isNumber }
        let zone = rest.dropFirst(digits.count)
        let trimmed = value[..<dot] + "." + String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0) + zone
        return try? Date(String(trimmed), strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}

import Foundation

protocol ReaderRepository: Sendable {
    func opened(mediaID: String, chapterID: String) async throws
    func pages(chapterID: String) async throws -> [String]
    func image(path: String) async throws -> Data
    func progress(mediaID: String, chapterID: String, value: Double, completed: Bool) async throws
    func download(mediaID: String, chapterIDs: [String]) async throws
    /// The chapter's synced reading progress and bookmark, fresh from the server.
    func chapterState(chapterID: String) async throws -> ReaderChapterState?
    func setBookmarked(mediaID: String, chapterID: String, bookmarked: Bool) async throws
}

extension ReaderRepository {
    func opened(mediaID: String, chapterID: String) async throws {}
    func chapterState(chapterID: String) async throws -> ReaderChapterState? { nil }
    func setBookmarked(mediaID: String, chapterID: String, bookmarked: Bool) async throws {}
}

/// Server-side state of one chapter, shared by the manga and novel readers.
struct ReaderChapterState: Equatable, Sendable {
    struct Progress: Equatable, Sendable {
        var progress: Double
        var completed: Bool
        var updatedAt: Date?
    }
    var progress: Progress?
    var bookmarked: Bool

    /// The page to reopen at, from synced progress (page = progress × count).
    /// Completed chapters start over.
    func page(count: Int) -> Int? {
        guard let progress, !progress.completed, count > 0 else { return nil }
        return min(max(Int((progress.progress * Double(count)).rounded()), 1), count)
    }
}

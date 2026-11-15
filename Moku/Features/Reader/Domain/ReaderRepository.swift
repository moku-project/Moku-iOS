import Foundation

protocol ReaderRepository: Sendable {
    func opened(mediaID: String, chapterID: String) async throws
    func pages(chapterID: String) async throws -> [String]
    func image(path: String) async throws -> Data
    func progress(mediaID: String, chapterID: String, value: Double, completed: Bool) async throws
    func download(mediaID: String, chapterIDs: [String]) async throws
    /// The chapter's synced reading progress, fresh from the server.
    func chapterState(chapterID: String) async throws -> ReaderChapterState?
}

extension ReaderRepository {
    func opened(mediaID: String, chapterID: String) async throws {}
    func chapterState(chapterID: String) async throws -> ReaderChapterState? { nil }
}

/// Server-side state of one chapter, shared by the manga and novel readers.
struct ReaderChapterState: Equatable, Sendable {
    struct Progress: Equatable, Sendable {
        var progress: Double
        var completed: Bool
        var updatedAt: Date?
    }
    var progress: Progress?

    /// The page to reopen at (progress × count); completed chapters start over.
    func page(count: Int) -> Int? {
        guard let progress, !progress.completed, count > 0 else { return nil }
        return min(max(Int((progress.progress * Double(count)).rounded()), 1), count)
    }
}

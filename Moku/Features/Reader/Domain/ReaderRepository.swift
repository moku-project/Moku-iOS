import Foundation

protocol ReaderRepository: Sendable {
    func opened(mediaID: String, chapterID: String) async throws
    func pages(chapterID: String) async throws -> [String]
    func image(path: String) async throws -> Data
    func progress(mediaID: String, chapterID: String, value: Double, completed: Bool) async throws
    func download(mediaID: String, chapterIDs: [String]) async throws
}

extension ReaderRepository {
    func opened(mediaID: String, chapterID: String) async throws {}
}

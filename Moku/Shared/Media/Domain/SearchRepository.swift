import Foundation

protocol SearchRepository: Sendable {
    func popular(options: SearchOptions) async throws -> DiscoveryPage
    func sources() async throws -> [SearchSource]
    func search(_ request: SearchRequest) async throws -> [MediaEntry]
    func search(
        _ request: SearchRequest,
        onUpdate: @escaping @Sendable ([MediaEntry]) async -> Void
    ) async throws -> [MediaEntry]
    /// The result's chapter count at its source, or nil when unknowable (fixtures, library search).
    func chapterCount(_ entry: MediaEntry) async throws -> Int?
}

struct DiscoveryPage: Sendable {
    var entries: [MediaEntry]
    var message: String? = nil
}

extension SearchRepository {
    func popular(options: SearchOptions) async throws -> DiscoveryPage {
        DiscoveryPage(entries: [])
    }
    func chapterCount(_ entry: MediaEntry) async throws -> Int? { nil }

    func search(
        _ request: SearchRequest,
        onUpdate: @escaping @Sendable ([MediaEntry]) async -> Void
    ) async throws -> [MediaEntry] {
        try await search(request)
    }
}

enum SearchFailure: LocalizedError {
    case notConnected
    var errorDescription: String? { "The source runtime isn’t ready. Try again in a moment." }
}

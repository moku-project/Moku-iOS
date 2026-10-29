import Foundation

protocol SearchRepository: Sendable {
    func latest(options: SearchOptions) async throws -> DiscoveryPage
    func popular(options: SearchOptions) async throws -> DiscoveryPage
    func genres(for entry: MediaEntry) async throws -> [String]
    func sources() async throws -> [SearchSource]
    func search(_ request: SearchRequest) async throws -> [MediaEntry]
    func search(
        _ request: SearchRequest,
        onUpdate: @escaping @Sendable ([MediaEntry]) async -> Void
    ) async throws -> [MediaEntry]
    /// How many chapters a result really has at its source, or nil when that
    /// can't be known (fixtures, library search).
    func chapterCount(_ entry: MediaEntry) async throws -> Int?
}

struct DiscoveryPage: Sendable {
    var entries: [MediaEntry]
    var message: String? = nil
}

extension SearchRepository {
    func latest(options: SearchOptions) async throws -> DiscoveryPage { DiscoveryPage(entries: []) }
    func popular(options: SearchOptions) async throws -> DiscoveryPage { DiscoveryPage(entries: []) }
    func genres(for entry: MediaEntry) async throws -> [String] { [] }
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

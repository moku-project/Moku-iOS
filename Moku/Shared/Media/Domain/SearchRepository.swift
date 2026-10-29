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
}

struct DiscoveryPage: Sendable {
    var entries: [MediaEntry]
    var message: String? = nil
}

extension SearchRepository {
    func latest(options: SearchOptions) async throws -> DiscoveryPage { DiscoveryPage(entries: []) }
    func popular(options: SearchOptions) async throws -> DiscoveryPage { DiscoveryPage(entries: []) }
    func genres(for entry: MediaEntry) async throws -> [String] { [] }

    func search(
        _ request: SearchRequest,
        onUpdate: @escaping @Sendable ([MediaEntry]) async -> Void
    ) async throws -> [MediaEntry] {
        try await search(request)
    }
}

enum SearchFailure: LocalizedError {
    case notConnected
    var errorDescription: String? { "Search is not available yet." }
}

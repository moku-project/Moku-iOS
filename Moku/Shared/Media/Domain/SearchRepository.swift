import Foundation

protocol SearchRepository: Sendable {
    func sources() async throws -> [SearchSource]
    func search(_ request: SearchRequest) async throws -> [MediaEntry]
    func search(
        _ request: SearchRequest,
        onUpdate: @escaping @Sendable ([MediaEntry]) async -> Void
    ) async throws -> [MediaEntry]
}

extension SearchRepository {
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

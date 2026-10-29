import Foundation
import ImageIO

actor BackendAPI {
    static let shared = BackendAPI()
    // Actor initializers run on their caller. Defer session/cache setup until
    // an actor-isolated request, so creating a screen never does service setup.
    private lazy var coverCache = ResourceCache(
        memoryLimit: 24 * 1024 * 1024, cancelWhenUnused: true,
        directory: URL.cachesDirectory.appending(path: "Moku/Covers-v1"))
    private lazy var queries = ResourceCache(
        memoryLimit: 8 * 1024 * 1024, cancelWhenUnused: true,
        directory: URL.cachesDirectory.appending(path: "Moku/Results-v1"),
        diskLimit: 32 * 1024 * 1024)
    private let backend = Backend.shared
    private lazy var session = URLSession(
        configuration: .ephemeral, delegate: LocalRedirectPolicy(), delegateQueue: nil)
    private lazy var imageSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 30
        return URLSession(
            configuration: configuration, delegate: LocalRedirectPolicy(), delegateQueue: nil)
    }()

    /// Only explicitly opted-in reads are cached. Mutations invalidate metadata
    /// before and after completion, including reads started while a write ran.
    func graphql<T: Decodable & Sendable>(
        _ query: String, cacheFor lifetime: TimeInterval = 0,
        refresh: Bool = false, requiresSourceRuntime: Bool = true
    ) async throws -> T {
        try Task.checkCancellation()
        let mutation = query.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("mutation")
        if mutation || refresh { await queries.clear() }
        do {
            let data: Data
            if lifetime > 0 && !mutation {
                data = try await queries.value(for: query, lifetime: lifetime) {
                    let data = try await self.fetchGraphQL(
                        query, requiresSourceRuntime: requiresSourceRuntime)
                    let _: T = try Self.decode(data)
                    return data
                }
            } else {
                data = try await fetchGraphQL(query, requiresSourceRuntime: requiresSourceRuntime)
            }
            if mutation { await queries.clear() }
            return try Self.decode(data)
        } catch {
            if mutation { await queries.clear() }
            throw error
        }
    }

    private func fetchGraphQL(_ query: String, requiresSourceRuntime: Bool) async throws -> Data {
        let connection = try await backend.connection(requiresSourceRuntime: requiresSourceRuntime)
        let (data, response) = try await session.data(for: connection.graphqlRequest(query: query))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw EmbeddedSearchError.message(
                "The embedded backend could not complete the request. Try again.")
        }
        return data
    }

    private nonisolated static func decode<T: Decodable & Sendable>(_ data: Data) throws -> T {
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        if let errors = envelope.errors, !errors.isEmpty {
            throw EmbeddedSearchError.message(
                "The source could not complete the request. Check your connection and try again.")
        }
        guard let result = envelope.data else {
            throw EmbeddedSearchError.message("The source returned an empty response. Try again.")
        }
        return result
    }

    /// Keep proxy paths relative: the backend port and token are session-specific.
    nonisolated static func coverURL(_ value: String?) -> URL? {
        guard let value, let parts = URLComponents(string: value) else { return nil }
        if let scheme = parts.scheme {
            guard ["https", "http"].contains(scheme.lowercased()),
                parts.host != nil, parts.user == nil, parts.password == nil
            else { return nil }
            let encoded = Data(value.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
            return URL(string: "/proxy/img/" + encoded)
        }
        guard parts.host == nil, parts.query == nil, parts.fragment == nil,
            parts.path.hasPrefix("/proxy/img/") || parts.path.hasPrefix("/proxy/cover/")
                || BackendController.Connection.isExtensionIconPath(parts.path),
            !parts.path.contains("..")
        else { return nil }
        return parts.url
    }

    func coverData(for url: URL) async throws -> Data {
        guard let resource = Self.coverURL(url.absoluteString) else {
            throw EmbeddedSearchError.message("Cover unavailable.")
        }
        return try await coverCache.value(for: resource.relativeString, lifetime: 7 * 24 * 60 * 60)
        {
            let connection = try await self.backend.connection(
                requiresSourceRuntime: resource.path.hasPrefix("/proxy/cover/")
                    && !resource.path.hasPrefix("/proxy/cover/remote/"))
            let request = try connection.coverRequest(path: resource.relativeString)
            let (data, response) = try await self.imageSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                http.mimeType?.hasPrefix("image/") == true, !data.isEmpty,
                data.count <= 16 * 1024 * 1024,
                let image = CGImageSourceCreateWithData(data as CFData, nil),
                CGImageSourceGetCount(image) > 0
            else {
                throw EmbeddedSearchError.message("Cover unavailable.")
            }
            return data
        }
    }

    func api(path: String, method: String = "GET", body: Data? = nil, contentType: String = "application/json") async throws -> Data {
        let connection = try await backend.connection(requiresSourceRuntime: false)
        var request = try connection.apiRequest(path: path, method: method, body: body)
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw EmbeddedSearchError.message("The server could not complete this action.")
        }
        return data
    }

    func chapterOpened(mediaID: String, chapterID: String) async throws {
        let connection = try await backend.connection()
        let request = try connection.chapterOpenRequest(mediaID: mediaID, chapterID: chapterID)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw EmbeddedSearchError.message("Couldn’t apply chapter download policies.")
        }
    }

    func readerPageData(path: String) async throws -> Data {
        let connection = try await backend.connection()
        // Only use backend-returned content paths; keep source cookies and headers in its proxy.
        let request = try connection.contentRequest(path: path)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
            http.mimeType?.hasPrefix("image/") == true, !data.isEmpty
        else {
            throw EmbeddedSearchError.message("Couldn’t load this page. Tap to retry.")
        }
        try Task.checkCancellation()
        return data
    }

    func trimMemory() async {
        await queries.trimMemory()
        await coverCache.trimMemory()
        await CoverImagePipeline.shared.trimMemory()
    }

    func clearContentCache() async {
        await queries.clear()
        await clearCoverCache()
    }

    func clearCoverCache() async {
        await CoverImagePipeline.shared.clear()
        await coverCache.clear()
    }

    static func literal(_ value: String) -> String {
        // JSON string syntax is compatible with a GraphQL quoted string, including escaping.
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }

    private struct Envelope<T: Decodable>: Decodable {
        let data: T?
        let errors: [GraphQLError]?
    }
    private struct GraphQLError: Decodable { let message: String }
}

private final class LocalRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

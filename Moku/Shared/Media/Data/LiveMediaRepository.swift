import Foundation

actor LiveMediaRepository: SearchRepository {
    static let shared = LiveMediaRepository()
    // Home and Details can request the same title during a tab transition.
    var chaptersSyncedAt: [String: Date] = [:]
    var chapterRequests: [String: Task<[Chapter], Error>] = [:]
    func sources() async throws -> [SearchSource] {
        let response: Installed = try await BackendAPI.shared.graphql(
            "{ installedExtensions { packageName displayName lang contentType enabled } }",
            cacheFor: 30, requiresSourceRuntime: false)
        return response.installedExtensions.filter(\.enabled).map { item in
            SearchSource(
                id: item.packageName, name: item.displayName, language: item.lang,
                media: Self.media(item.contentType), isPinned: false)
        }
    }

    func search(_ request: SearchRequest) async throws -> [MediaEntry] {
        try await search(request, onUpdate: { _ in })
    }

    func search(
        _ request: SearchRequest,
        onUpdate: @escaping @Sendable ([MediaEntry]) async -> Void
    ) async throws -> [MediaEntry] {
        let options = request.options
        guard options.genres.isEmpty, options.statuses.isEmpty, options.method != .tags else {
            throw EmbeddedSearchError.message(
                "Genre and status filters are not supported by the embedded search yet. Clear them and use a keyword."
            )
        }
        guard !request.query.isEmpty else { return [] }
        let available = try await sources()
        let selected = available.filter {
            (options.sourceID == nil || options.sourceID == $0.id)
                && (options.media == .all || options.media == $0.media)
                && (options.language == nil || $0.language == "all"
                    || options.language == $0.language)
        }
        guard !selected.isEmpty else {
            throw EmbeddedSearchError.message(
                available.isEmpty
                    ? "No sources installed. Open Extensions from the More menu to add one."
                    : "No installed source matches your search filters. Clear the filters or choose a different content type."
            )
        }
        let batches: [Result<[MediaEntry], any Error>] = try await concurrentMap(
            selected, limit: 3,
            onUpdate: { batches in
                await onUpdate(batches.compactMap { try? $0.get() }.flatMap { $0 })
            },
            transform: { source in
                do {
                    let query =
                        "{ search(extensionId: \(BackendAPI.literal(source.id)), query: \(BackendAPI.literal(request.query)), page: 1) { results { id externalId title contentType thumbnailUrl } hasNextPage } }"
                    let response: SearchResponse = try await BackendAPI.shared.graphql(
                        query, cacheFor: 60)
                    return .success(
                        response.search.results.map {
                            MediaEntry(
                                id: $0.id, title: $0.title, media: Self.media($0.contentType),
                                sourceName: source.name,
                                coverURL: BackendAPI.coverURL($0.thumbnailUrl),
                                extensionID: source.id, externalID: $0.externalId)
                        })
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // One unavailable source must not cancel the other sources.
                    return .failure(error)
                }
            })
        return try batches.flatMap { try $0.get() }
    }

    func genres(for entry: MediaEntry) async throws -> [String] {
        try await metadata(for: entry, refresh: false).genres
    }

    func popular(options: SearchOptions) async throws -> DiscoveryPage {
        try await discoveryListing(options: options, field: "popularManga")
    }

    func latest(options: SearchOptions) async throws -> DiscoveryPage {
        try await discoveryListing(options: options, field: "latestUpdates")
    }

    private func discoveryListing(options: SearchOptions, field: String) async throws -> DiscoveryPage {
        let available = try await sources()
        let selected = available.filter {
            (options.media == .all || $0.media == options.media)
                && (options.sourceID == nil || $0.id == options.sourceID)
                && (options.language == nil || $0.language == "all" || $0.language == options.language)
        }
        guard !selected.isEmpty else {
            return DiscoveryPage(entries: [], message: available.isEmpty
                ? "Add a source in More → Extensions to discover titles."
                : "No installed sources match this mode and language.")
        }
        let batches: [Result<[MediaEntry], any Error>] = try await concurrentMap(selected, limit: 3) { source in
            do {
                struct Response: Decodable, Sendable { let listing: SearchResponse.Page }
                let response: Response = try await BackendAPI.shared.graphql(
                    "{ listing: \(field)(extensionId: \(BackendAPI.literal(source.id)), page: 1) { results { id externalId title contentType thumbnailUrl } hasNextPage } }",
                    cacheFor: 300)
                return .success(response.listing.results.prefix(12).map {
                    MediaEntry(id: $0.id, title: $0.title, media: Self.media($0.contentType),
                        sourceName: source.name, coverURL: BackendAPI.coverURL($0.thumbnailUrl),
                        extensionID: source.id, externalID: $0.externalId)
                })
            } catch is CancellationError { throw CancellationError() }
            catch { return .failure(error) }
        }
        let pages = batches.compactMap { try? $0.get() }
        var entries: [MediaEntry] = []
        var seen = Set<String>()
        // Interleave sources so a single catalog cannot fill the whole shelf.
        for index in 0..<12 {
            for page in pages where index < page.count {
                let entry = page[index]
                if seen.insert(DiscoveryRanking.key(entry)).inserted { entries.append(entry) }
            }
        }
        return DiscoveryPage(entries: Array(entries.prefix(36)), message: pages.count < batches.count
            ? "Some sources couldn’t load. Try again to refresh discovery titles." : nil)
    }

    private static func media(_ value: String) -> ContentMode {
        switch value {
        case "ANIME": .anime
        case "NOVEL": .novels
        default: .manga
        }
    }

    private struct Installed: Decodable, Sendable { let installedExtensions: [SourceDTO] }
    private struct SourceDTO: Decodable, Sendable {
        let packageName: String
        let displayName: String
        let lang: String
        let contentType: String
        let enabled: Bool
    }
    private struct SearchResponse: Decodable, Sendable {
        struct Page: Decodable, Sendable {
            let results: [MediaDTO]
            let hasNextPage: Bool
        }
        let search: Page
    }
    private struct MediaDTO: Decodable, Sendable {
        let id: String
        let externalId: String
        let title: String
        let contentType: String
        let thumbnailUrl: String?
    }
}

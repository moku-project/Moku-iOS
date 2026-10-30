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
        let pinned = SourcePins.all
        return response.installedExtensions.filter(\.enabled).map { item in
            SearchSource(
                id: item.packageName, name: item.displayName, language: item.lang,
                media: Self.media(item.contentType), isPinned: pinned.contains(item.packageName))
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
        let statuses = options.statuses.subtracting([.any])
        let tagSearch = !options.genres.isEmpty || !statuses.isEmpty
        guard tagSearch || !request.query.isEmpty else { return [] }
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
        // Each source answers independently, so a slow one must not hold the others back.
        let batches: [Result<[MediaEntry], any Error>] = try await concurrentMap(
            selected, limit: 6,
            onUpdate: { batches in
                await onUpdate(batches.compactMap { try? $0.get() }.flatMap { $0 })
            },
            transform: { source in
                do {
                    // Desktop TagTab: genres map onto each source's own filter tree.
                    // "Match any" runs one filtered search per genre and merges them.
                    var filterSets: [String] = [""]
                    if tagSearch {
                        let nodes = try await self.filterOptions(source.id)
                        let genreSets: [Set<String>] = options.genres.isEmpty ? [[]]
                            : options.match == .all ? [options.genres] : options.genres.sorted().prefix(4).map { [$0] }
                        filterSets = genreSets.compactMap { genres in
                            let built = FilterBuilder.inputs(nodes, genres: genres, statuses: Set(statuses.map(\.rawValue)))
                            return built.matchedAll ? built.literal : nil
                        }
                        // A source that has no such genre can't answer; skip it rather than
                        // returning unfiltered results.
                        if filterSets.isEmpty { return .success([]) }
                    }
                    var entries: [MediaEntry] = []
                    var seen = Set<String>()
                    for filters in filterSets {
                        let query =
                            "{ search(extensionId: \(BackendAPI.literal(source.id)), query: \(BackendAPI.literal(request.query)), page: \(max(1, request.page))\(filters.isEmpty ? "" : ", filters: \(filters)")) { results { id externalId title contentType thumbnailUrl } hasNextPage } }"
                        let response: SearchResponse = try await BackendAPI.shared.graphql(
                            query, cacheFor: 300)
                        for item in response.search.results where seen.insert(item.externalId).inserted {
                            entries.append(MediaEntry(
                                id: item.id, title: item.title, media: Self.media(item.contentType),
                                sourceName: source.name,
                                coverURL: BackendAPI.coverURL(item.thumbnailUrl),
                                extensionID: source.id, externalID: item.externalId))
                        }
                    }
                    return .success(entries)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // One unavailable source must not cancel the other sources.
                    return .failure(error)
                }
            })
        return try batches.flatMap { try $0.get() }
    }

    private var filterCache: [String: [FilterBuilder.Node]] = [:]

    func filterOptions(_ extensionID: String) async throws -> [FilterBuilder.Node] {
        if let cached = filterCache[extensionID] { return cached }
        struct Response: Decodable, Sendable { let filterOptions: [FilterBuilder.Node] }
        let leaf = "__typename ... on CheckBoxFilter { name } ... on TriStateFilter { name } ... on SelectFilter { name values }"
        let response: Response = try await BackendAPI.shared.graphql(
            "{ filterOptions(extensionId: \(BackendAPI.literal(extensionID))) { \(leaf) ... on GroupFilter { name children { \(leaf) } } } }",
            cacheFor: 3600)
        filterCache[extensionID] = response.filterOptions
        return response.filterOptions
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
        let batches: [Result<[MediaEntry], any Error>] = try await concurrentMap(selected, limit: 6) { source in
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


/// Desktop `pinnedSourceIds`: pinned sources sort first in pickers and search.
enum SourcePins {
    private static let key = "search.pinnedSources"
    nonisolated static var all: Set<String> {
        Set((UserDefaults.standard.string(forKey: key) ?? "").split(separator: ",").map(String.init))
    }
    nonisolated static func toggle(_ id: String) {
        var pins = all
        if !pins.insert(id).inserted { pins.remove(id) }
        UserDefaults.standard.set(pins.sorted().joined(separator: ","), forKey: key)
    }
}

/// Port of desktop `buildGenreFilterInputs`, extended to status: tri-state and
/// checkbox filters named after a genre are switched on, and a select filter
/// named "Status" picks the matching value.
enum FilterBuilder {
    struct Node: Decodable, Sendable {
        let typename: String
        let name: String?
        let values: [String]?
        let children: [Node]?
        private enum CodingKeys: String, CodingKey {
            case typename = "__typename", name, values, children
        }
    }

    nonisolated static func inputs(_ nodes: [Node], genres: Set<String>, statuses: Set<String>)
        -> (literal: String, matchedAll: Bool)
    {
        let wantGenres = Set(genres.map { $0.lowercased() })
        let wantStatus = Set(statuses.map { $0.lowercased() })
        var matchedGenres = Set<String>()
        var matchedStatus = false

        func walk(_ list: [Node]) -> [String] {
            list.compactMap { node in
                guard let name = node.name else { return nil }
                let key = name.lowercased()
                switch node.typename {
                case "GroupFilter":
                    let kids = walk(node.children ?? [])
                    return kids.isEmpty ? nil : "{name: \(BackendAPI.literal(name)), group: {children: [\(kids.joined(separator: ","))]}}"
                case "TriStateFilter" where wantGenres.contains(key) || wantStatus.contains(key):
                    if wantGenres.contains(key) { matchedGenres.insert(key) } else { matchedStatus = true }
                    return "{name: \(BackendAPI.literal(name)), tristate: {state: 1}}"
                case "CheckBoxFilter" where wantGenres.contains(key) || wantStatus.contains(key):
                    if wantGenres.contains(key) { matchedGenres.insert(key) } else { matchedStatus = true }
                    return "{name: \(BackendAPI.literal(name)), checkbox: {state: true}}"
                case "SelectFilter" where key.contains("status") && !wantStatus.isEmpty:
                    guard let index = node.values?.firstIndex(where: { wantStatus.contains($0.lowercased()) }) else { return nil }
                    matchedStatus = true
                    return "{name: \(BackendAPI.literal(name)), select: {state: \(index)}}"
                default:
                    return nil
                }
            }
        }
        let inputs = walk(nodes)
        let ok = matchedGenres.count == wantGenres.count && (wantStatus.isEmpty || matchedStatus)
        return ("[\(inputs.joined(separator: ","))]", ok)
    }
}

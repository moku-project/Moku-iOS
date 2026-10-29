import Foundation

/// A snapshot of the active profile's saved titles. Never calls installed sources.
struct LibrarySearchRepository: SearchRepository {
    let entries: [MediaEntry]

    private func sourceID(_ entry: MediaEntry) -> String {
        entry.extensionID ?? "local:\(entry.sourceName)"
    }

    func sources() async throws -> [SearchSource] {
        var order: [String] = []
        var first: [String: MediaEntry] = [:]
        var media: [String: Set<ContentMode>] = [:]
        for entry in entries {
            let id = sourceID(entry)
            if first[id] == nil { first[id] = entry; order.append(id) }
            media[id, default: []].insert(entry.media)
        }
        return order.compactMap { id in
            guard let entry = first[id] else { return nil }
            return SearchSource(id: id, name: entry.sourceName, language: "all",
                                media: media[id]?.count == 1 ? entry.media : .all, isPinned: false)
        }
    }

    func search(_ request: SearchRequest) async throws -> [MediaEntry] {
        try Task.checkCancellation()
        return entries.filter {
            $0.title.localizedStandardContains(request.query)
                && (request.options.media == .all || $0.media == request.options.media)
                && (request.options.sourceID == nil || sourceID($0) == request.options.sourceID)
        }
    }
}

/// Reads the same filtered, ordered Library snapshot used by the page.
@MainActor
final class ScopedLibrarySearchRepository: SearchRepository {
    let snapshot: @MainActor () async -> [MediaEntry]
    init(snapshot: @escaping @MainActor () async -> [MediaEntry]) { self.snapshot = snapshot }
    func sources() async throws -> [SearchSource] { [] }
    nonisolated func search(_ request: SearchRequest) async throws -> [MediaEntry] {
        let entries = await snapshot()
        try Task.checkCancellation()
        return entries.filter {
            request.query.isEmpty || $0.title.localizedStandardContains(request.query)
        }
    }
}

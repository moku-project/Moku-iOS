import Foundation

/// A snapshot of the active profile's saved titles. Never calls installed sources.
struct LibrarySearchRepository: SearchRepository {
    let entries: [MediaEntry]

    private func sourceID(_ entry: MediaEntry) -> String {
        entry.extensionID ?? "local:\(entry.sourceName)"
    }

    func sources() async throws -> [SearchSource] {
        var seen: Set<String> = []
        return entries.compactMap { entry in
            let id = sourceID(entry)
            guard seen.insert(id).inserted else { return nil }
            let media = Set(entries.filter { sourceID($0) == id }.map(\.media))
            return SearchSource(
                id: id, name: entry.sourceName, language: "all",
                media: media.count == 1 ? entry.media : .all, isPinned: false)
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
    let snapshot: @MainActor () -> [MediaEntry]
    init(snapshot: @escaping @MainActor () -> [MediaEntry]) { self.snapshot = snapshot }
    func sources() async throws -> [SearchSource] { [] }
    func search(_ request: SearchRequest) async throws -> [MediaEntry] {
        try Task.checkCancellation()
        return snapshot().filter {
            request.query.isEmpty || $0.title.localizedStandardContains(request.query)
        }
    }
}

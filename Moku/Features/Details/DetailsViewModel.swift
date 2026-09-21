import Foundation
import Observation

@MainActor @Observable final class DetailsViewModel {
    let entry: MediaEntry
    private let repository: any DetailsRepository
    var details: MediaDetails?
    var error: String?
    var chapterError: String?
    var loading = true
    private var generation = UUID()

    init(
        entry: MediaEntry, repository: any DetailsRepository = LiveMediaRepository.shared
    ) {
        self.entry = entry
        self.repository = repository
    }

    var emptyChapterMessage: String {
        if entry.media == .anime {
            return
                "\(entry.sourceName) returned no episodes for this title. Check the source’s availability and language settings, then refresh."
        }
        return
            "\(entry.sourceName) returned no readable chapters for this title. A title can have metadata and a cover even when the source has no chapters available. Check the source’s availability and language settings, then refresh."
    }

    var sourceURL: URL? {
        guard entry.extensionID == "eu.kanade.tachiyomi.extension.all.mangadex",
            let externalID = entry.externalID, externalID.hasPrefix("/manga/"),
            let id = externalID.split(separator: "/").last, UUID(uuidString: String(id)) != nil
        else { return nil }
        return URL(string: "https://mangadex.org/title/\(id)")
    }

    func load(refresh: Bool = false) async {
        let current = UUID()
        generation = current
        loading = true
        error = nil
        chapterError = nil
        defer { if generation == current { loading = false } }
        do {
            var metadata = try await repository.metadata(for: entry, refresh: refresh)
            try Task.checkCancellation()
            guard generation == current else { return }
            // Retain the previous list during refresh, including a failed refresh.
            if let details, details.id == metadata.id { metadata.chapters = details.chapters }
            details = metadata
        } catch {
            guard !Task.isCancelled, generation == current else { return }
            self.error = "Couldn’t refresh title details. Check your connection and try again."
        }
        guard !Task.isCancelled, generation == current, let id = details?.id else { return }
        do {
            let chapters = try await repository.chapters(mediaID: id)
            try Task.checkCancellation()
            guard generation == current else { return }
            details?.chapters = chapters
        } catch {
            guard !Task.isCancelled, generation == current else { return }
            chapterError =
                "Couldn’t load chapters from \(entry.sourceName). This is a request failure, not an empty chapter list. Check your connection or source settings and retry."
        }
    }
}

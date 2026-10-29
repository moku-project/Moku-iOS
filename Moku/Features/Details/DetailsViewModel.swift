import Foundation
import Observation

@MainActor @Observable final class DetailsViewModel {
    let entry: MediaEntry
    private let repository: any DetailsRepository
    var details: MediaDetails? {
        didSet {
            chapterRevision &+= 1
            completedCount = details?.chapters.reduce(0) { $0 + ($1.completed ? 1 : 0) } ?? 0
        }
    }
    private(set) var chapterRevision = 0
    private(set) var completedCount = 0
    var error: String?
    var chapterError: String?
    var loading = true
    private var generation = UUID()

    init(
        entry: MediaEntry, repository: any DetailsRepository = AppDependencies.detailsRepository
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

    /// Desktop "Start / Continue · Ch X / Read again": the chapter after the last
    /// completed one in reading order.
    func continueTarget(preferences: Data) -> (chapter: Chapter, label: String)? {
        guard let details else { return nil }
        let ordered = ChapterPresentation.readingOrder(details.chapters, preferences: preferences, mediaID: entry.id)
        guard let first = ordered.first else { return nil }
        let verb = entry.media == .anime ? "watching" : "reading"
        guard let last = ordered.lastIndex(where: \.completed) else {
            return (first, "Start \(verb)")
        }
        guard ordered.indices.contains(last + 1) else {
            return (first, entry.media == .anime ? "Watch again" : "Read again")
        }
        let next = ordered[last + 1]
        let number = next.number.map { "\(entry.media == .anime ? "Ep" : "Ch") \($0.formatted())" } ?? next.label
        return (next, "Continue · \(number)")
    }

    func setRead(_ ids: Set<String>, read: Bool) async {
        guard var updated = details, !ids.isEmpty else { return }
        let mediaID = updated.id
        let previous = updated.chapters
        // Update rows immediately; the server confirms or the list is restored.
        // Build the new value first: reading `details` inside its own mutation traps.
        updated.chapters = previous.map { chapter in
            var chapter = chapter
            if ids.contains(chapter.id) { chapter.completed = read }
            return chapter
        }
        details = updated
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                "mutation { markChaptersRead(mediaId: \(BackendAPI.literal(mediaID)), chapterIds: [\(ids.map(BackendAPI.literal).joined(separator: ","))], read: \(read)) { id } }",
                requiresSourceRuntime: false)
            if read { await pushTrackerProgress(mediaID: mediaID, chapters: updated.chapters) }
        } catch {
            if var restored = details {
                restored.chapters = previous
                details = restored
            }
            chapterError = "Couldn’t update read state. Try again."
        }
    }

    /// Desktop pushTrackerProgress: after marking read on the series page, raise
    /// each linked tracker to the highest read chapter number. The server also
    /// syncs in the background; this makes the tracker update immediate.
    private func pushTrackerProgress(mediaID: String, chapters: [Chapter]) async {
        guard let highest = chapters.filter(\.completed).compactMap(\.number).max() else { return }
        struct Response: Decodable, Sendable {
            struct Media: Decodable, Sendable {
                struct Link: Decodable, Sendable { let id: String; let lastChapterRead: Double }
                let trackLinks: [Link]
            }
            let media: Media?
        }
        guard let response: Response = try? await BackendAPI.shared.graphql(
            "{ media(id: \(BackendAPI.literal(mediaID))) { trackLinks { id lastChapterRead } } }",
            requiresSourceRuntime: false) else { return }
        for link in response.media?.trackLinks ?? [] where highest > link.lastChapterRead {
            let _: IgnoredGraphQLResult? = try? await BackendAPI.shared.graphql(
                "mutation { updateTrack(linkId: \(BackendAPI.literal(link.id)), lastChapterRead: \(highest)) { id } }",
                requiresSourceRuntime: false)
        }
    }

    func download(_ ids: [String]) async {
        guard let mediaID = details?.id, !ids.isEmpty else { return }
        guard await StorageGuard.allow(count: ids.count, media: entry.media) else { return }
        do {
            struct Queued: Decodable, Sendable { struct Item: Decodable, Sendable { let id: String }; let enqueueDownload: [Item] }
            let _: Queued = try await BackendAPI.shared.graphql(
                "mutation { enqueueDownload(mediaId: \(BackendAPI.literal(mediaID)), chapterIds: [\(ids.map(BackendAPI.literal).joined(separator: ","))]) { id } }",
                requiresSourceRuntime: false)
            Toaster.shared.show(ids.count == 1 ? "Download queued" : "\(ids.count) downloads queued", kind: .download)
        } catch { chapterError = "Couldn’t queue downloads. Try again." }
    }

    func deleteDownloads(_ ids: [String]) async {
        guard let mediaID = details?.id, !ids.isEmpty else { return }
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                "mutation { deleteDownload(mediaId: \(BackendAPI.literal(mediaID)), chapterIds: [\(ids.map(BackendAPI.literal).joined(separator: ","))]) }",
                requiresSourceRuntime: false)
            let removed = Set(ids)
            if var updated = details {
                updated.chapters = updated.chapters.map { chapter in
                    var chapter = chapter
                    if removed.contains(chapter.id) { chapter.downloaded = false }
                    return chapter
                }
                details = updated
            }
            Toaster.shared.show(ids.count == 1 ? "Download deleted" : "\(ids.count) downloads deleted")
        } catch { chapterError = "Couldn’t delete downloads. Try again." }
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
            let chapters = try await repository.chapters(mediaID: id, refresh: refresh)
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

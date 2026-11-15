import Foundation
import OSLog
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

    /// The source answered with a browser challenge (Cloudflare and the like).
    private static let log = Logger(subsystem: "com.moku.app", category: "details")
    var sourceChallenge = false

    var sourceURL: URL? {
        guard entry.extensionID == "example.source",
            let externalID = entry.externalID, externalID.hasPrefix("/manga/"),
            let id = externalID.split(separator: "/").last, UUID(uuidString: String(id)) != nil
        else { return nil }
        return URL(string: "https://example.org/title/\(id)")
    }

    /// The title on its source site, resolved once the extension's base URL is known.
    private(set) var browserURL: URL?

    func loadBrowserURL() async {
        guard browserURL == nil, let id = details?.id else { return }
        browserURL = await SourceLink.url(mediaID: id) ?? sourceURL
    }

    /// Titles pulled from their trackers recently, so reopening a title doesn't pull again.
    private static var trackerPulledAt: [String: Date] = [:]

    /// Quietly pulls read progress from linked trackers, then rereads it.
    func pullTrackerIfNeeded() async {
        guard let mediaID = details?.id, Int64(mediaID) != nil else { return }
        if let last = Self.trackerPulledAt[mediaID], Date.now.timeIntervalSince(last) < 600 { return }
        Self.trackerPulledAt[mediaID] = .now
        struct Links: Decodable, Sendable {
            struct Media: Decodable, Sendable { struct Link: Decodable, Sendable { let id: String }; let trackLinks: [Link] }
            let media: Media?
        }
        guard let links: Links = try? await BackendAPI.shared.graphql(
            "{ media(id: \(BackendAPI.literal(mediaID))) { trackLinks { id } } }", requiresSourceRuntime: false),
            !(links.media?.trackLinks.isEmpty ?? true)
        else { return }
        struct Pulled: Decodable, Sendable { struct Link: Decodable, Sendable { let id: String }; let pullTracker: [Link] }
        guard (try? await BackendAPI.shared.graphql(
            "mutation { pullTracker(mediaId: \(BackendAPI.literal(mediaID))) { id } }",
            requiresSourceRuntime: false) as Pulled) != nil
        else { return }
        await refreshReadProgress()
    }

    /// Rereads read state from the database without asking the source again.
    func refreshReadProgress() async {
        guard let mediaID = details?.id else { return }
        struct Response: Decodable, Sendable {
            struct Item: Decodable, Sendable { let id: String; let completed: Bool; let readingProgress: Chapter.Progress? }
            struct Media: Decodable, Sendable { let chapters: [Item] }
            let media: Media?
        }
        guard let response: Response = try? await BackendAPI.shared.graphql(
            "{ media(id: \(BackendAPI.literal(mediaID))) { chapters { id completed readingProgress { progress positionSeconds } } } }",
            requiresSourceRuntime: false),
            details?.id == mediaID, let items = response.media?.chapters
        else { return }
        let states = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        guard details?.chapters.contains(where: { chapter in
            states[chapter.id].map { $0.completed != chapter.completed || $0.readingProgress != chapter.readingProgress } ?? false
        }) == true else { return }
        updateChapters { chapter in
            if let state = states[chapter.id] {
                chapter.completed = state.completed
                chapter.readingProgress = state.readingProgress
            }
        }
    }

    /// "Start / Continue · Ch X / Read again": the chapter after the last completed one in reading order.
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
        // Optimistic (restored on failure); build the value first, as reading `details` inside its own mutation traps.
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

    /// Raises each linked tracker to the highest read chapter now instead of waiting for the server's background sync.
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
            struct Queued: Decodable, Sendable {
                struct Item: Decodable, Sendable {
                    let chapterId: String
                    let status: Chapter.DownloadJob.Status?
                    let progress: Double?
                }
                let enqueueDownload: [Item]
            }
            let queued: Queued = try await BackendAPI.shared.graphql(
                "mutation { enqueueDownload(mediaId: \(BackendAPI.literal(mediaID)), chapterIds: [\(ids.map(BackendAPI.literal).joined(separator: ","))]) { chapterId status progress } }",
                requiresSourceRuntime: false)
            // Show the queue on the rows right away; polling takes it from here.
            let jobs = Dictionary(
                queued.enqueueDownload.map {
                    ($0.chapterId, Chapter.DownloadJob(status: $0.status ?? .queued, progress: $0.progress ?? 0))
                }, uniquingKeysWith: { _, last in last })
            updateChapters { chapter in
                if let job = jobs[chapter.id] { chapter.download = job }
            }
            Toaster.shared.show(ids.count == 1 ? "Download queued" : "\(ids.count) downloads queued", kind: .download)
        } catch { chapterError = "Couldn’t queue downloads. Try again." }
    }

    /// True while any chapter on this page is queued or downloading.
    var hasActiveDownloads: Bool { details?.chapters.contains(where: \.isDownloadActive) ?? false }

    /// Light refresh of download state only, used while downloads run.
    func refreshDownloads() async {
        guard let mediaID = details?.id else { return }
        struct Response: Decodable, Sendable {
            struct Item: Decodable, Sendable {
                let id: String
                let downloaded: Bool
                let download: Chapter.DownloadJob?
            }
            struct Media: Decodable, Sendable { let chapters: [Item] }
            let media: Media?
        }
        guard let response: Response = try? await BackendAPI.shared.graphql(
            "{ media(id: \(BackendAPI.literal(mediaID))) { chapters { id downloaded download { status progress } } } }",
            requiresSourceRuntime: false),
            !Task.isCancelled, details?.id == mediaID, let items = response.media?.chapters
        else { return }
        let states = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var changed = false
        var updated = details?.chapters ?? []
        for index in updated.indices {
            guard let state = states[updated[index].id] else { continue }
            if updated[index].downloaded != state.downloaded || updated[index].download != state.download {
                updated[index].downloaded = state.downloaded
                updated[index].download = state.download
                changed = true
            }
        }
        // Only touch `details` when something moved, so idle polls don't rebuild the list.
        if changed { details?.chapters = updated }
    }

    func retryDownload(_ id: String) async {
        guard let mediaID = details?.id else { return }
        let previous = details?.chapters.first { $0.id == id }?.download
        updateChapters { if $0.id == id { $0.download = .init(status: .queued) } }
        do {
            struct Retry: Decodable, Sendable { struct Value: Decodable, Sendable { let id: String }; let retryDownload: Value }
            let _: Retry = try await BackendAPI.shared.graphql(
                "mutation { retryDownload(mediaId: \(BackendAPI.literal(mediaID)), chapterId: \(BackendAPI.literal(id))) { id } }",
                requiresSourceRuntime: false)
        } catch {
            updateChapters { if $0.id == id { $0.download = previous } }
            chapterError = "Couldn’t retry the download. Try again."
        }
    }

    /// Removes a queued or running download.
    func cancelDownload(_ id: String) async {
        guard let mediaID = details?.id else { return }
        let previous = details?.chapters.first { $0.id == id }?.download
        updateChapters { if $0.id == id { $0.download = nil } }
        do {
            struct Cancelled: Decodable, Sendable { let dequeueDownload: Bool }
            let _: Cancelled = try await BackendAPI.shared.graphql(
                "mutation { dequeueDownload(mediaId: \(BackendAPI.literal(mediaID)), chapterId: \(BackendAPI.literal(id))) }",
                requiresSourceRuntime: false)
        } catch {
            updateChapters { if $0.id == id { $0.download = previous } }
            chapterError = "Couldn’t cancel the download. Try again."
        }
    }

    /// Mihon-style chapter bookmarks, updated optimistically.
    func setBookmarked(_ ids: Set<String>, bookmarked: Bool) async {
        guard let mediaID = details?.id, !ids.isEmpty else { return }
        let previous = details?.chapters ?? []
        updateChapters { if ids.contains($0.id) { $0.bookmarked = bookmarked } }
        do {
            struct Response: Decodable, Sendable {
                struct Item: Decodable, Sendable { let id: String; let bookmarked: Bool }
                let setChaptersBookmarked: [Item]
            }
            let _: Response = try await BackendAPI.shared.graphql(
                "mutation { setChaptersBookmarked(mediaId: \(BackendAPI.literal(mediaID)), chapterIds: [\(ids.map(BackendAPI.literal).joined(separator: ","))], bookmarked: \(bookmarked)) { id bookmarked } }",
                requiresSourceRuntime: false)
        } catch {
            if var restored = details, restored.id == mediaID {
                // Restore only the bookmark flags, keeping any newer download or read state.
                let flags = Dictionary(previous.map { ($0.id, $0.bookmarked) }, uniquingKeysWith: { _, last in last })
                restored.chapters = restored.chapters.map { chapter in
                    var chapter = chapter
                    if ids.contains(chapter.id), let flag = flags[chapter.id] { chapter.bookmarked = flag }
                    return chapter
                }
                details = restored
            }
            chapterError = "Couldn’t update bookmarks. Try again."
        }
    }

    /// Builds the new list first: reading `details` inside its own mutation traps.
    private func updateChapters(_ change: (inout Chapter) -> Void) {
        guard var updated = details else { return }
        updated.chapters = updated.chapters.map { chapter in
            var chapter = chapter
            change(&chapter)
            return chapter
        }
        details = updated
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
        sourceChallenge = false
        defer { if generation == current { loading = false } }
        // Search and library titles carry the media ID, so chapters load alongside the title info.
        let early: Task<[Chapter], Error>? =
            details == nil || details?.id == entry.id
            ? Task { [repository, entry] in try await repository.chapters(mediaID: entry.id, refresh: refresh) }
            : nil
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
        guard !Task.isCancelled, generation == current, let id = details?.id else {
            early?.cancel()
            return
        }
        do {
            let chapters: [Chapter]
            if let early, id == entry.id {
                chapters = try await withTaskCancellationHandler {
                    try await early.value
                } onCancel: { early.cancel() }
            } else {
                early?.cancel()
                chapters = try await repository.chapters(mediaID: id, refresh: refresh)
            }
            try Task.checkCancellation()
            guard generation == current else { return }
            details?.chapters = chapters
        } catch {
            guard !Task.isCancelled, generation == current else { return }
            sourceChallenge = BrowserVerification.isChallenge(error)
            Self.log.error("chapters for \(self.entry.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            chapterError =
                "Couldn’t load chapters from \(entry.sourceName). This is a request failure, not an empty chapter list. Check your connection or source settings and retry."
        }
    }
}

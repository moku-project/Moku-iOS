import Foundation
import Observation

@MainActor @Observable final class NovelReaderViewModel {
    let details: MediaDetails
    /// Reading order: oldest first, so "next" always means the following chapter.
    let chapters: [Chapter]
    private(set) var chapterID: String
    private(set) var document: NovelDocument?
    private(set) var loading = true
    var error: String?
    /// Fraction of the chapter scrolled past, 0…1.
    var progress: Double = 0
    /// Set once per chapter load; the view scrolls there after layout.
    private(set) var resumeAt: Double?
    private(set) var activityEntry: HomeEntry
    private var savedProgress: [String: (Double, Bool)] = [:]
    private var saveTask: Task<Void, Never>?
    private var generation = UUID()
    /// A bookmark jump: where the next load scrolls, instead of synced progress.
    private var pendingResume: Double?

    init(details: MediaDetails, chapterID: String, preferences: Data) {
        self.details = details
        self.chapterID = chapterID
        chapters = ChapterPresentation.readingOrder(details.chapters, preferences: preferences, mediaID: details.id)
        activityEntry = HomeEntry(
            id: details.id, title: details.title, coverURL: BackendAPI.coverURL(details.thumbnailUrl),
            media: "Novels", genres: details.genres,
            unreadCount: details.chapters.filter { !$0.completed }.count,
            chapters: details.chapters.map {
                HomeChapter(id: $0.id, title: $0.label, isRead: $0.completed, uploadedAt: $0.uploadedAt)
            }, author: details.byline, summary: details.description)
    }

    var chapter: Chapter? { chapters.first { $0.id == chapterID } }
    var index: Int { chapters.firstIndex { $0.id == chapterID } ?? 0 }
    var previous: Chapter? { chapters.indices.contains(index - 1) ? chapters[index - 1] : nil }
    var next: Chapter? { chapters.indices.contains(index + 1) ? chapters[index + 1] : nil }
    var completed: Bool { progress >= 0.97 }
    var ready: Bool { !loading && error == nil && document != nil }

    func load() async {
        let id = chapterID
        let current = UUID()
        generation = current
        loading = true
        error = nil
        document = nil
        progress = 0
        resumeAt = nil
        do {
            async let text = BackendAPI.shared.chapterText(mediaID: details.id, chapterID: id)
            async let saved = savedPosition(chapterID: id)
            let (body, isHTML) = try await text
            let parsed = await Task.detached(priority: .userInitiated) {
                NovelDocument.parse(body, isHTML: isHTML)
            }.value
            let resume = await saved
            try Task.checkCancellation()
            guard generation == current else { return }
            document = parsed
            // A finished chapter reopens at the top rather than at its last line.
            resumeAt = pendingResume ?? resume.map { $0 >= 0.97 ? 0 : $0 }
            pendingResume = nil
            loading = false
            Task { try? await BackendAPI.shared.chapterOpened(mediaID: details.id, chapterID: id) }
        } catch {
            guard !Task.isCancelled, generation == current else { return }
            loading = false
            self.error = (error as? EmbeddedSearchError)?.errorDescription
                ?? "Couldn’t load this chapter. Check your connection and try again."
        }
    }

    func didResume() { resumeAt = nil }

    func open(_ chapter: Chapter) {
        guard chapter.id != chapterID else { return }
        flush()
        chapterID = chapter.id
    }

    /// Opens a bookmark: scrolls within this chapter, or loads its chapter there.
    func open(_ bookmark: NovelBookmark) {
        if bookmark.chapterID == chapterID {
            resumeAt = bookmark.fraction
        } else if let chapter = chapters.first(where: { $0.id == bookmark.chapterID }) {
            pendingResume = bookmark.fraction
            open(chapter)
        }
    }

    /// Moving to the next chapter counts the current one as read, like desktop.
    func advance() {
        guard let next else { return }
        progress = 1
        scheduleSave(immediately: true)
        open(next)
    }

    func scrolled(to fraction: Double) {
        let value = min(1, max(0, fraction))
        guard abs(value - progress) >= 0.005 || (value >= 0.97) != completed else { return }
        progress = value
        scheduleSave()
    }

    func flush() { scheduleSave(immediately: true) }

    private func scheduleSave(immediately: Bool = false) {
        guard ready || immediately else { return }
        let mediaID = details.id, chapterID = chapterID
        let value = progress, done = completed
        if let saved = savedProgress[chapterID], abs(saved.0 - value) < 0.01, saved.1 == done { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .seconds(2)) }
            guard !Task.isCancelled else { return }
            do {
                let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                    """
                    mutation { updateReadingProgress(mediaId: \(BackendAPI.literal(mediaID)),
                    chapterId: \(BackendAPI.literal(chapterID)), progress: \(value), completed: \(done)) { progress } }
                    """, requiresSourceRuntime: false)
                self?.savedProgress[chapterID] = (value, done)
            } catch {
                guard !Task.isCancelled else { return }
                Toaster.shared.show("Progress couldn’t sync", detail: "Moku will retry when you keep reading.", kind: .error)
            }
        }
    }

    private nonisolated func savedPosition(chapterID: String) async -> Double? {
        struct Response: Decodable, Sendable {
            struct Chapter: Decodable, Sendable {
                struct Progress: Decodable, Sendable { let progress: Double }
                let readingProgress: Progress?
            }
            let chapter: Chapter?
        }
        let response: Response? = try? await BackendAPI.shared.graphql(
            "{ chapter(id: \(BackendAPI.literal(chapterID))) { readingProgress { progress } } }",
            requiresSourceRuntime: false)
        return response?.chapter?.readingProgress?.progress
    }
}

/// Desktop's novel bookmark: one saved spot per series, separate from progress.
struct NovelBookmark: Codable, Equatable, Sendable {
    var chapterID: String
    var fraction: Double

    static func all(_ data: Data) -> [String: NovelBookmark] {
        (try? JSONDecoder().decode([String: NovelBookmark].self, from: data)) ?? [:]
    }
    static func encode(_ value: [String: NovelBookmark]) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}

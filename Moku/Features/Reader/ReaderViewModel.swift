import Foundation
import Observation

@MainActor @Observable final class ReaderViewModel {
    let details: MediaDetails
    let repository: any ReaderRepository
    let preferences: ReaderPreferences
    private(set) var activityEntry: HomeEntry
    @ObservationIgnored private var activityPrepared = false
    var chapterID: String
    var pages: [String] = []
    var page = 1
    var loading = true
    var error: String?
    var notice: String?
    var downloadBusy = false
    var drawerOpen = false
    var chromeVisible = true
    var landscape = false
    var jumpID = UUID()
    /// Desktop resume banner: the saved page this chapter reopened at.
    var resumedPage: Int?
    private var committedProgress: [String: (Double, Bool)] = [:]
    private var pendingProgress: [String: (Double, Bool)] = [:]
    private var progressTask: Task<Void, Never>?
    private var loadedChapterID: String?
    private var completedChapters = Set<String>()
    private var loadGeneration = UUID()
    /// The next chapter's first pages, fetched near the end of this one so the
    /// chapter turn shows pages at once instead of a skeleton.
    @ObservationIgnored private var prefetched: [String: Data] = [:]
    @ObservationIgnored private var prefetchedChapter: String?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?

    init(
        details: MediaDetails, chapterID: String, preferences: ReaderPreferences,
        repository: any ReaderRepository = LiveReaderRepository()
    ) {
        self.details = details
        self.activityEntry = HomeEntry(id: details.id, title: details.title, media: "Manga")
        self.chapterID = chapterID
        self.preferences = preferences
        self.repository = repository
        completedChapters = Set(details.chapters.filter(\.completed).map(\.id))
    }
    var activityReady: Bool {
        loadedChapterID == chapterID && !loading && error == nil && !pages.isEmpty
    }
    var chapter: Chapter? { details.chapters.first { $0.id == chapterID } }
    var settings: MangaReadingSettings {
        get { preferences.settings(for: details.id) }
        set { preferences.set(newValue, for: details.id) }
    }
    var behaviour: ReaderBehaviour { preferences.document.behaviour }
    var isStrip: Bool { settings.pageStyle == "longstrip" }
    var isDouble: Bool {
        settings.pageStyle == "double" || settings.pageStyle == "auto" && landscape
    }
    var groups: [[Int]] {
        ReaderPagination.groups(
            count: pages.count, double: isDouble, offset: settings.offsetDoubleSpreads)
    }
    var visiblePages: [Int] { groups.first { $0.contains(page) } ?? [page] }
    var bookmarked: Bool {
        preferences.document.bookmarks[details.id]
            == ReaderPosition(chapterID: chapterID, page: page)
    }
    var chapterIndex: Int { details.chapters.firstIndex { $0.id == chapterID } ?? 0 }
    var canPrevious: Bool { (!isStrip && page > 1) || chapterIndex > 0 }
    var canNext: Bool {
        (!isStrip && (visiblePages.max() ?? page) < pages.count)
            || chapterIndex + 1 < details.chapters.count
    }

    func load() async {
        let id = chapterID
        let generation = UUID()
        loadGeneration = generation
        loading = true
        error = nil
        pages = []
        loadedChapterID = nil
        do {
            if !activityPrepared {
                let details = details
                let prepared = await Task.detached(priority: .userInitiated) {
                    HomeEntry(id: details.id, title: details.title,
                              coverURL: BackendAPI.coverURL(details.thumbnailUrl), media: "Manga",
                              genres: details.genres, unreadCount: details.chapters.filter { !$0.completed }.count,
                              chapters: details.chapters.map {
                                  HomeChapter(id: $0.id, title: $0.label, isRead: $0.completed, uploadedAt: $0.uploadedAt)
                              }, author: details.byline, summary: details.description)
                }.value
                try Task.checkCancellation()
                guard loadGeneration == generation else { return }
                activityEntry = prepared
                activityPrepared = true
            }
            let result = try await repository.pages(chapterID: id)
            try Task.checkCancellation()
            guard chapterID == id, loadGeneration == generation else { return }
            pages = result
            prefetched = prefetched.filter { result.contains($0.key) }
            let saved = preferences.document.positions[details.id]
            page = saved?.chapterID == id ? min(max(saved?.page ?? 1, 1), result.count) : 1
            resumedPage = page > 1 ? page : nil
            loadedChapterID = id
            loading = false
            jumpID = UUID()
            do {
                try await repository.opened(mediaID: details.id, chapterID: id)
            } catch is CancellationError {} catch {
                if chapterID == id {
                    notice = "Chapter opened, but automatic download policies couldn’t be applied."
                }
            }
        } catch is CancellationError {
        } catch {
            guard chapterID == id, loadGeneration == generation else { return }
            self.error = error.localizedDescription
            loading = false
        }
    }
    func image(path: String) async throws -> Data {
        if let data = prefetched.removeValue(forKey: path) { return data }
        return try await repository.image(path: path)
    }
    private func prefetchNextChapter() {
        let index = chapterIndex + 1
        let ahead = min(6, behaviour.preloadPages)
        guard ahead > 0, details.chapters.indices.contains(index), !pages.isEmpty else { return }
        let reached = isStrip ? page : (visiblePages.max() ?? page)
        guard pages.count - reached < max(2, behaviour.preloadPages) else { return }
        let next = details.chapters[index].id
        guard prefetchTask == nil, prefetchedChapter != next else { return }
        prefetchedChapter = next
        let repository = repository
        prefetchTask = Task { [weak self] in
            defer { self?.prefetchTask = nil }
            guard let paths = try? await repository.pages(chapterID: next) else { return }
            for path in paths.prefix(ahead) {
                guard !Task.isCancelled, let self, self.prefetchedChapter == next else { return }
                if let data = try? await repository.image(path: path) { self.prefetched[path] = data }
            }
        }
    }
    func jump(_ value: Int) {
        guard !pages.isEmpty else { return }
        page = min(max(value, 1), pages.count)
        jumpID = UUID()
        recordProgress()
    }
    func visiblePageChanged(_ value: Int) {
        guard value != page, !loading else { return }
        page = value
        recordProgress()
    }
    func navigate(forward: Bool) {
        if !isStrip,
            let next = ReaderPagination.adjacent(page: page, groups: groups, forward: forward)
        {
            jump(next)
        } else {
            changeChapter(forward: forward)
        }
    }
    func changeChapter(forward: Bool) {
        let index = chapterIndex + (forward ? 1 : -1)
        guard details.chapters.indices.contains(index) else { return }
        selectChapter(details.chapters[index].id, markRead: forward && behaviour.markReadOnNext)
    }
    func selectChapter(_ id: String, markRead: Bool = false) {
        guard id != chapterID else { return }
        recordProgress(forceComplete: markRead)
        if prefetchedChapter != id {
            prefetchTask?.cancel()
            prefetchedChapter = nil
            prefetched.removeAll()
        }
        chapterID = id
        loading = true
        page = 1
    }
    func toggleBookmark() {
        if bookmarked {
            preferences.document.bookmarks.removeValue(forKey: details.id)
        } else {
            preferences.document.bookmarks[details.id] = ReaderPosition(
                chapterID: chapterID, page: page)
        }
    }
    func recordProgress(forceComplete: Bool = false) {
        guard loadedChapterID == chapterID, !pages.isEmpty else { return }
        prefetchNextChapter()
        if behaviour.autoBookmark {
            let position = ReaderPosition(chapterID: chapterID, page: page)
            if preferences.document.positions[details.id] != position {
                preferences.document.positions[details.id] = position
            }
        }
        let complete =
            forceComplete
            || ((isStrip ? page : (visiblePages.max() ?? page)) == pages.count
                && behaviour.autoMarkRead)
            || completedChapters.contains(chapterID)
        if complete { completedChapters.insert(chapterID) }
        let value = Double(isStrip ? page : (visiblePages.max() ?? page)) / Double(pages.count)
        if let committed = committedProgress[chapterID], committed.0 == value, committed.1 == complete,
           pendingProgress[chapterID] == nil { return }
        pendingProgress[chapterID] = (value, complete)
        startProgressWriter()
    }
    private func startProgressWriter() {
        guard progressTask == nil else { return }
        progressTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self else { return }
            while let (id, progress) = pendingProgress.first {
                pendingProgress.removeValue(forKey: id)
                do {
                    try await repository.progress(
                        mediaID: details.id, chapterID: id,
                        value: progress.0, completed: progress.1)
                    committedProgress[id] = progress
                } catch {
                    notice = "Progress is saved on this device, but couldn’t sync. Try again."
                }
            }
            progressTask = nil
        }
    }
    func flush() async {
        recordProgress()
        await progressTask?.value
        await preferences.flush()
    }
    func download(_ ids: [String]) async {
        guard !ids.isEmpty, !downloadBusy else { return }
        guard await StorageGuard.allow(count: ids.count, media: .manga) else { return }
        downloadBusy = true
        defer { downloadBusy = false }
        do {
            try await repository.download(mediaID: details.id, chapterIDs: ids)
            notice = "Added \(ids.count) chapter\(ids.count == 1 ? "" : "s") to downloads."
        } catch { notice = "Couldn’t queue downloads. Try again." }
    }
}

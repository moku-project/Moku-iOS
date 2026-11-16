import Foundation
import Observation

@MainActor @Observable final class RecentViewModel {
    static func makeDefault() -> RecentViewModel {
        #if DEBUG
            if PreviewMode.isEnabled
                || ProcessInfo.processInfo.arguments.contains("--ui-testing-recent")
            {
                return RecentViewModel(repository: RecentPreviewData.Repository())
            }
        #endif
        return RecentViewModel()
    }
    var updates: [RecentUpdate] = []
    var loading = false
    var refreshing = false
    var done = 0
    var total = 0
    var failedTitles: [String] = []
    var error: String?
    var notice: String?
    var busy: Set<String> = []
    var queued: Set<String> = []
    private let repository: any RecentRepository
    init(repository: any RecentRepository = LiveRecentRepository()) {
        self.repository = repository
    }

    func load(entries: [MediaEntry], refresh: Bool = false) async -> Bool {
        guard !loading else { return false }
        loading = true
        refreshing = refresh
        done = 0
        total = entries.count
        failedTitles = []
        error = nil
        defer {
            loading = false
            refreshing = false
        }
        if repository.hasServerFeed, let feed = await loadFromServer(refresh: refresh) {
            return feed
        }
        let previous = updates
        var result: [RecentUpdate] = []
        var newCount = 0
        for entry in entries {
            if Task.isCancelled { return false }
            do {
                // Capture a baseline before syncing, including the first visit to Recent.
                let baseline =
                    refresh ? try await repository.chapters(for: entry, refresh: false) : []
                let items = try await repository.chapters(for: entry, refresh: refresh)
                if refresh {
                    let known = Set(baseline.map(\.id))
                    newCount += items.filter { !known.contains($0.id) }.count
                }
                result.append(contentsOf: items)
            } catch {
                if Task.isCancelled { return false }
                failedTitles.append(entry.title)
                result.append(contentsOf: previous.filter { $0.entry.id == entry.id })
            }
            done += 1
        }
        guard !Task.isCancelled else { return false }
        let collected = result
        let sorted = await Task.detached(priority: .userInitiated) {
            collected.sorted {
                let left = $0.chapter.date ?? .distantPast
                let right = $1.chapter.date ?? .distantPast
                return left == right ? $0.id > $1.id : left > right
            }
        }.value
        guard !Task.isCancelled else { return false }
        updates = sorted
        if !failedTitles.isEmpty {
            error =
                "Couldn’t update \(failedTitles.count) title(s): \(failedTitles.joined(separator: ", "))."
        }
        if refresh {
            notice =
                failedTitles.isEmpty
                ? "Library update complete · \(newCount) new chapters / episodes"
                : "Update finished with \(failedTitles.count) failed title(s) · \(newCount) new chapters / episodes"
        }
        return failedTitles.isEmpty
    }

    var currentTitle: String?

    /// Updates the whole library on the server (honouring folder update flags); nil when there is no server feed.
    private func loadFromServer(refresh: Bool) async -> Bool? {
        do {
            if refresh {
                try await repository.startLibraryUpdate()
                try await Task.sleep(for: .milliseconds(300))
                var status = try await repository.libraryUpdateStatus()
                while status.running {
                    total = status.total
                    done = status.done
                    currentTitle = status.currentTitle
                    try await Task.sleep(for: .seconds(1))
                    status = try await repository.libraryUpdateStatus()
                }
                done = status.done
                total = status.total
                currentTitle = nil
                failedTitles = status.failedTitles
                let count = status.newChapterCount
                Toaster.shared.show(
                    failedTitles.isEmpty
                        ? "Library update complete"
                        : "\(failedTitles.count) series failed to update",
                    detail: count == 0
                        ? "Nothing new."
                        : "\(count) new chapter\(count == 1 ? "" : "s") or episode\(count == 1 ? "" : "s").",
                    kind: failedTitles.isEmpty ? .success : .error)
            }
            guard let feed = try await repository.serverFeed() else { return nil }
            guard !Task.isCancelled else { return false }
            updates = feed
            if !failedTitles.isEmpty {
                error =
                    "Couldn’t update \(failedTitles.count) title(s): \(failedTitles.prefix(5).joined(separator: ", "))."
            }
            return failedTitles.isEmpty
        } catch is CancellationError {
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            self.error = "Couldn’t load library updates. Check your connection and try again."
            return false
        }
    }

    func act(on update: RecentUpdate, delete: Bool) async {
        guard busy.insert(update.id).inserted else { return }
        defer { busy.remove(update.id) }
        do {
            try await repository.download(update, delete: delete)
            if delete {
                if let index = updates.firstIndex(where: { $0.id == update.id }) {
                    updates[index].chapter.downloaded = false
                }
                queued.remove(update.id)
            } else {
                queued.insert(update.id)
            }
            Toaster.shared.show(
                delete ? "Download deleted" : "Download queued", kind: delete ? .success : .download
            )
        } catch {
            notice =
                delete
                ? "Couldn’t delete the download. Try again."
                : "Couldn’t queue the download. Try again."
        }
    }

    func entry(id: String) async throws -> MediaEntry { try await repository.entry(id: id) }

    nonisolated static func history(
        _ sessions: [HistorySession], entries: [String: HomeEntry], query: String, mode: ContentMode
    ) -> [RecentHistoryTitle] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = sessions.filter { session in
            (mode == .all || session.media == mode)
                && (query.isEmpty || session.title.localizedStandardContains(query)
                    || session.endChapterTitle?.localizedStandardContains(query) == true)
        }
        return Dictionary(grouping: matching, by: \.mediaID).map { id, values in
            let ordered = values.sorted { $0.endedAt > $1.endedAt }
            let latest = ordered[0]
            let entry =
                entries[id]
                ?? HomeEntry(
                    id: id, title: latest.title, coverURL: latest.coverURL,
                    media: latest.media.title,
                    unreadCount: latest.unreadCount)
            return RecentHistoryTitle(entry: entry, sessions: ordered)
        }.sorted { $0.latest.endedAt > $1.latest.endedAt }
    }

    func visibleUpdates(query: String, mode: ContentMode) -> [RecentUpdate] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(
            updates.filter {
                (mode == .all || $0.entry.media == mode)
                    && (query.isEmpty
                        || $0.entry.title.localizedStandardContains(query)
                        || $0.chapter.label.localizedStandardContains(query))
            }.prefix(100))
    }
}

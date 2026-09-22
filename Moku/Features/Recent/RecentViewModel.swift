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
        updates = result.sorted {
            let left = $0.chapter.date ?? .distantPast
            let right = $1.chapter.date ?? .distantPast
            return left == right ? $0.id > $1.id : left > right
        }
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
            notice = delete ? "Download deleted." : "Download queued."
        } catch {
            notice =
                delete
                ? "Couldn’t delete the download. Try again."
                : "Couldn’t queue the download. Try again."
        }
    }

    func entry(id: String) async throws -> MediaEntry { try await repository.entry(id: id) }

    static func history(_ snapshot: HomeSnapshot, query: String, mode: ContentMode)
        -> [RecentHistoryTitle]
    {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = Dictionary(
            snapshot.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let sessions = snapshot.sessions.filter { session in
            guard let entry = entries[session.entryID],
                mode == .all || entry.media.lowercased() == mode.rawValue
            else { return false }
            return query.isEmpty || entry.title.localizedStandardContains(query)
                || (entry.chapters.first { $0.id == session.chapterID }?.title
                    .localizedStandardContains(
                        query) ?? false)
        }
        return Dictionary(grouping: sessions, by: \.entryID).compactMap { id, values in
            guard let entry = entries[id] else { return nil }
            return RecentHistoryTitle(
                entry: entry, sessions: values.sorted { $0.endedAt > $1.endedAt })
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

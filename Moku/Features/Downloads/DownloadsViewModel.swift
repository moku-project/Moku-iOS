import Foundation
import Observation

/// Download queue and actions backed by the bundled server.
@MainActor @Observable
final class DownloadsViewModel {
    var entries: [DownloadEntry] {
        didSet {
            let ids = Set(entries.lazy.filter { $0.status == .completed }.map(\.titleID))
            if completedTitleIDs != ids { completedTitleIDs = ids }
        }
    }
    private(set) var completedTitleIDs: Set<String>
    @ObservationIgnored private let loader = DownloadSnapshotLoader()
    var isPaused = false {
        didSet {
            guard live, !applyingSnapshot, isPaused != oldValue else { return }
            let next = isPaused
            Task { await action(next ? "stopDownloader" : "startDownloader") }
        }
    }
    private var applyingSnapshot = false
    private let live: Bool
    private var refreshing = false
    private var lastRetry: [String: Date] = [:]
    var notice: String?
    var autoRetry = false

    init(entries: [DownloadEntry] = [], live: Bool = false) {
        self.entries = entries
        self.completedTitleIDs = Set(entries.lazy.filter { $0.status == .completed }.map(\.titleID))
        self.live = live
    }
    func refresh() async {
        guard live, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let snapshot = try await loader.load()
            try Task.checkCancellation()
            if entries != snapshot.entries { entries = snapshot.entries }
            DownloadAlerts.shared.observe(
                snapshot.entries.map {
                    .init(titleID: $0.titleID, chapterID: $0.id, title: $0.title, status: $0.status)
                })
            applyingSnapshot = true
            isPaused = !snapshot.running
            applyingSnapshot = false
            notice = nil
            if autoRetry {
                for entry in entries
                where entry.status == .failed
                    && Date().timeIntervalSince(lastRetry[entry.id] ?? .distantPast) >= 60
                {
                    lastRetry[entry.id] = Date()
                    retry(entryID: entry.id)
                }
            }
        } catch { if !Task.isCancelled { notice = "Couldn’t refresh downloads. Try again." } }
    }
    private func action(_ mutation: String, refreshAfter: Bool = true) async {
        do {
            let _: [String: Bool] = try await BackendAPI.shared.graphql(
                "mutation { \(mutation) }", requiresSourceRuntime: false)
            if refreshAfter { await refresh() }
        } catch { notice = "Couldn’t update downloads. Try again." }
    }

    /// Queued or failed chapters leave the queue; finished ones delete their files.
    func remove(_ targets: [DownloadEntry]) {
        Task {
            var failed = false
            for entry in targets {
                do {
                    if entry.status == .completed {
                        let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                            "mutation { deleteDownload(mediaId: \(BackendAPI.literal(entry.titleID)), chapterIds: [\(BackendAPI.literal(entry.id))]) }",
                            requiresSourceRuntime: false)
                    } else {
                        let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                            "mutation { dequeueDownload(mediaId: \(BackendAPI.literal(entry.titleID)), chapterId: \(BackendAPI.literal(entry.id))) }",
                            requiresSourceRuntime: false)
                    }
                } catch { failed = true }
            }
            await refresh()
            Toaster.shared.show(
                failed
                    ? "Some downloads couldn’t be removed"
                    : targets.count == 1
                        ? "Download removed" : "Removed \(targets.count) downloads",
                kind: failed ? .error : .success)
        }
    }

    func move(titleID: String, toTop: Bool) {
        let queue = entries.filter { $0.status == .queued || $0.status == .downloading }
        let mine = queue.filter { $0.titleID == titleID }
        guard !mine.isEmpty else { return }
        Task {
            do {
                for (offset, entry) in mine.enumerated() {
                    let position = toTop ? offset : queue.count - mine.count + offset
                    let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                        "mutation { reorderDownload(mediaId: \(BackendAPI.literal(titleID)), chapterId: \(BackendAPI.literal(entry.id)), position: \(position)) }",
                        requiresSourceRuntime: false)
                }
                await refresh()
            } catch { Toaster.shared.show("Couldn’t reorder the queue", kind: .error) }
        }
    }

    func reverse(titleID: String) {
        let queue = entries.filter { $0.status == .queued || $0.status == .downloading }
        let slots = queue.indices.filter {
            queue[$0].titleID == titleID && queue[$0].status == .queued
        }
        guard slots.count > 1 else { return }
        let reversed = slots.reversed().map { queue[$0] }
        if !live {
            var next = queue
            for (slot, entry) in zip(slots, reversed) { next[slot] = entry }
            entries = next + entries.filter { $0.status != .queued && $0.status != .downloading }
            return
        }
        reorder(Array(zip(reversed, slots)))
    }

    /// A chapter that is downloading stays first.
    func move(entryIDs: Set<String>, toTop: Bool) {
        let queue = entries.filter { $0.status == .queued || $0.status == .downloading }
        let first = queue.first?.status == .downloading ? 1 : 0
        let movable = queue.dropFirst(first)
        let pinned = movable.filter { entryIDs.contains($0.id) }
        guard !pinned.isEmpty else { return }
        let rest = movable.filter { !entryIDs.contains($0.id) }
        if !live {
            let ordered = Array(queue.prefix(first)) + (toTop ? pinned + rest : rest + pinned)
            entries = ordered + entries.filter { $0.status != .queued && $0.status != .downloading }
            return
        }
        let start = toTop ? first : queue.count - pinned.count
        reorder(pinned.enumerated().map { ($0.element, start + $0.offset) })
    }

    private func reorder(_ moves: [(DownloadEntry, Int)]) {
        Task {
            do {
                for (entry, position) in moves {
                    let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                        "mutation { reorderDownload(mediaId: \(BackendAPI.literal(entry.titleID)), chapterId: \(BackendAPI.literal(entry.id)), position: \(position)) }",
                        requiresSourceRuntime: false)
                }
                await refresh()
            } catch {
                await refresh()
                Toaster.shared.show("Couldn’t reorder the queue", kind: .error)
            }
        }
    }

    enum Placement { case top, up, down, bottom }

    func move(entryID: String, to placement: Placement) {
        let queue = entries.filter { $0.status == .queued || $0.status == .downloading }
        guard let index = queue.firstIndex(where: { $0.id == entryID }) else { return }
        let target: Int
        switch placement {
        case .top: target = 0
        case .up: target = max(0, index - 1)
        case .down: target = min(queue.count - 1, index + 1)
        case .bottom: target = queue.count - 1
        }
        guard target != index else { return }
        let entry = queue[index]
        Task {
            do {
                let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                    "mutation { reorderDownload(mediaId: \(BackendAPI.literal(entry.titleID)), chapterId: \(BackendAPI.literal(entry.id)), position: \(target)) }",
                    requiresSourceRuntime: false)
                await refresh()
            } catch { Toaster.shared.show("Couldn’t reorder the queue", kind: .error) }
        }
    }

    func count(history: Bool) -> Int {
        entries.filter { ($0.status == .completed) == history }.count
    }

    private func matches(_ entry: DownloadEntry, section: DownloadsSection, history: Bool) -> Bool {
        let inView =
            history
            ? entry.status == .completed || entry.status == .failed
            : entry.status != .completed
        return inView && section.includes(entry)
    }

    func count(section: DownloadsSection, history: Bool) -> Int {
        entries.filter { matches($0, section: section, history: history) }.count
    }

    func groups(section: DownloadsSection, history: Bool) -> [DownloadGroup] {
        grouped(entries.filter { matches($0, section: section, history: history) })
    }

    func clear(section: DownloadsSection, history: Bool) {
        let ids = Set(entries.filter { matches($0, section: section, history: history) }.map(\.id))
        if live {
            let targets = entries.filter { ids.contains($0.id) }
            Task {
                for entry in targets {
                    await action(
                        "dequeueDownload(mediaId: \(BackendAPI.literal(entry.titleID)), chapterId: \(BackendAPI.literal(entry.id)))",
                        refreshAfter: false)
                }
                await refresh()
            }
        } else {
            entries.removeAll { ids.contains($0.id) }
        }
    }

    func groups(history: Bool) -> [DownloadGroup] {
        grouped(entries.filter { ($0.status == .completed) == history })
    }

    private func grouped(_ visible: [DownloadEntry]) -> [DownloadGroup] {
        var order: [String] = []
        var grouped: [String: [DownloadEntry]] = [:]
        for entry in visible {
            if grouped[entry.titleID] == nil { order.append(entry.titleID) }
            grouped[entry.titleID, default: []].append(entry)
        }
        return order.map { DownloadGroup(id: $0, entries: grouped[$0] ?? []) }
    }

    func retry(entryID: String? = nil, titleID: String? = nil) {
        if live {
            let targets = entries.filter {
                $0.status == .failed && (entryID == nil || $0.id == entryID)
                    && (titleID == nil || $0.titleID == titleID)
            }
            Task {
                for entry in targets {
                    do {
                        struct Retry: Decodable, Sendable {
                            struct Value: Decodable, Sendable { let id: String }
                            let retryDownload: Value
                        }
                        let _: Retry = try await BackendAPI.shared.graphql(
                            "mutation { retryDownload(mediaId: \(BackendAPI.literal(entry.titleID)), chapterId: \(BackendAPI.literal(entry.id))) { id } }",
                            requiresSourceRuntime: false)
                    } catch { notice = "Couldn’t retry download." }
                }
                await refresh()
            }
            return
        }
        for index in entries.indices where entries[index].status == .failed {
            guard entryID == nil || entries[index].id == entryID,
                titleID == nil || entries[index].titleID == titleID
            else { continue }
            entries[index].status = .queued
            entries[index].progress = 0
        }
    }

    func clear(history: Bool) {
        entries.removeAll { ($0.status == .completed) == history }
    }

    static func makeDefault() -> DownloadsViewModel {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-downloads") {
                return DownloadsViewModel(entries: [
                    .init(
                        id: "1", titleID: "talent", title: "I’m Not That Kind of Talent",
                        chapter: "Chapter 14", status: .downloading, progress: 0.65),
                    .init(
                        id: "2", titleID: "talent", title: "I’m Not That Kind of Talent",
                        chapter: "Chapter 15", status: .queued),
                    .init(
                        id: "3", titleID: "monster", title: "Monster But Wild",
                        chapter: "Chapter 8", status: .failed),
                    .init(
                        id: "4", titleID: "monster", title: "Monster But Wild",
                        chapter: "Chapter 9", status: .failed),
                    .init(
                        id: "5", titleID: "overgeared", title: "Overgeared", chapter: "Chapter 24",
                        status: .queued),
                    .init(
                        id: "6", titleID: "history", title: "Omniscient Reader",
                        chapter: "Chapter 12", status: .completed, bytes: 24_000_000,
                        completedAt: Date()),
                ])
            }
        #endif
        return DownloadsViewModel(live: !PreviewMode.isEnabled)
    }
}

/// Joins queue data off the UI, fetching title names in batches only when missing or expired.
private actor DownloadSnapshotLoader {
    struct Snapshot: Sendable {
        let entries: [DownloadEntry]
        let running: Bool
    }
    private var names: [String: (title: String, cover: URL?, expires: Date)] = [:]

    func load() async throws -> Snapshot {
        struct ChapterInfo: Decodable, Sendable {
            let title: String?
            let number: Double?
        }
        struct Download: Decodable, Sendable {
            let id: String
            let mediaId: String
            let chapterId: String
            let chapter: ChapterInfo
            let status: String
            let progress: Double
            let downloadedBytes: Double?
            let completedAt: String?
        }
        struct Status: Decodable, Sendable { let isRunning: Bool }
        struct Result: Decodable, Sendable {
            let downloadQueue: [Download]
            let downloaderStatus: Status
        }
        let result: Result = try await BackendAPI.shared.graphql(
            "{ downloadQueue { id mediaId chapterId chapter { title number } status progress downloadedBytes completedAt } downloaderStatus { isRunning } }",
            requiresSourceRuntime: false)
        let ids = Set(result.downloadQueue.map(\.mediaId))
        names = names.filter { ids.contains($0.key) && $0.value.expires > .now }
        let missing = ids.filter { names[$0] == nil }.sorted()
        for offset in stride(from: 0, to: missing.count, by: 40) {
            try Task.checkCancellation()
            let batch = Array(missing.dropFirst(offset).prefix(40))
            let fields = batch.enumerated().map {
                "m\($0.offset): media(id: \(BackendAPI.literal($0.element))) { title thumbnailUrl }"
            }.joined(separator: " ")
            struct Title: Decodable, Sendable {
                let title: String
                let thumbnailUrl: String?
            }
            let response: [String: Title?] = try await BackendAPI.shared.graphql(
                "{ \(fields) }", requiresSourceRuntime: false)
            for (index, id) in batch.enumerated() {
                let media = response["m\(index)"] ?? nil
                names[id] = (
                    media?.title ?? "Title \(id)", BackendAPI.coverURL(media?.thumbnailUrl),
                    .now.addingTimeInterval(300)
                )
            }
        }
        try Task.checkCancellation()
        let formatter = ISO8601DateFormatter()
        let entries = result.downloadQueue.map { item in
            let status: DownloadStatus =
                switch item.status {
                case "DOWNLOADING": .downloading
                case "FAILED": .failed
                case "DONE": .completed
                default: .queued
                }
            return DownloadEntry(
                id: item.chapterId, titleID: item.mediaId,
                title: names[item.mediaId]?.title ?? "Title \(item.mediaId)",
                chapter: item.chapter.title ?? item.chapter.number.map {
                    "Chapter \($0.formatted())"
                } ?? "Chapter",
                status: status, progress: min(1, max(0, item.progress)),
                bytes: Int64(max(0, item.downloadedBytes ?? 0)),
                completedAt: item.completedAt.flatMap { formatter.date(from: $0) },
                coverURL: names[item.mediaId]?.cover)
        }
        return Snapshot(entries: entries, running: result.downloaderStatus.isRunning)
    }
}

import Foundation
import Observation

@MainActor @Observable final class TrackingViewModel {
    static func makeDefault() -> TrackingViewModel {
        #if DEBUG
            if PreviewMode.isEnabled
                || ProcessInfo.processInfo.arguments.contains("--ui-testing-tracking")
            {
                return TrackingViewModel(
                    repository: TrackingPreviewRepository(),
                    searchRepository: TrackingPreviewSearch())
            }
        #endif
        return TrackingViewModel()
    }
    var services: [TrackingService] = []
    var loading = false
    var working = false
    var notice: String?
    var items: [TrackingImportItem] = []
    var sources: [SearchSource] = []
    var media: ContentMode = .manga
    var statuses: Set<String> = ["CURRENT"]
    var sourceID: String?
    var language: String?
    var trackerKey = "anilist"
    var stopRequested = false
    var completed = 0
    private let repository: any TrackingRepository
    private let searchRepository: any SearchRepository
    @ObservationIgnored private var draftStore: TrackingDraftStore?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    private var importUsername: String?
    init(
        repository: any TrackingRepository = LiveTrackingRepository(),
        searchRepository: any SearchRepository = LiveMediaRepository.shared
    ) {
        self.repository = repository
        self.searchRepository = searchRepository
    }
    var importable: [TrackingImportItem] {
        items.filter { $0.state == .matched || $0.state == .failed }
    }
    var availableSources: [SearchSource] {
        sources.filter {
            $0.media == media
                && (language == nil || $0.language == language || $0.language == "all")
        }
    }
    func configure(directory: URL) async {
        guard draftStore == nil else { return }
        let store = TrackingDraftStore(url: directory.appending(path: "tracking-import.json"))
        draftStore = store
        guard let draft = try? await store.read() else { return }
        media = draft.media
        statuses = draft.statuses
        sourceID = draft.sourceID
        trackerKey = draft.trackerKey
        items = draft.items
        importUsername = draft.username
    }

    func persist() {
        guard let draftStore else { return }
        let draft = TrackingDraft(
            media: media, statuses: statuses, sourceID: sourceID,
            trackerKey: trackerKey, items: items, username: importUsername)
        let previous = pendingSave
        // A later snapshot must never be overwritten by an older queued save.
        pendingSave = Task {
            await previous?.value
            do { try await draftStore.write(draft) } catch {
                notice = "Couldn’t save import progress. Keep this page open and try again."
            }
        }
    }

    func flushDraft() async { await pendingSave?.value }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do { services = try await repository.services() } catch {
            notice = "Couldn’t load tracking services. Try Refresh."
        }
    }
    func connect(_ service: TrackingService, token: String) async -> Bool {
        guard !working else { return false }
        working = true
        defer { working = false }
        do {
            try await repository.login(
                key: service.key, token: token.trimmingCharacters(in: .whitespacesAndNewlines))
            await load()
            return true
        } catch {
            notice = "Couldn’t connect. Check the token or redirect URL and try again."
            return false
        }
    }
    func disconnect(_ service: TrackingService) async -> Bool {
        guard !working else { return false }
        working = true
        defer { working = false }
        do {
            try await repository.logout(key: service.key)
            await load()
            return true
        } catch {
            notice = "Couldn’t disconnect. Try again."
            return false
        }
    }
    func loadSources() async {
        do { sources = try await searchRepository.sources() } catch {
            notice = "Couldn’t load installed sources. You can retry or import without a source."
        }
    }
    func fetchList(library: LibraryStore) async -> Bool {
        guard !working, !statuses.isEmpty else { return false }
        working = true
        stopRequested = false
        defer {
            working = false
            persist()
        }
        do {
            let remote = try await repository.list(
                key: trackerKey, media: media, statuses: statuses)
            await library.load()
            let linked = try await repository.linkedIDs(key: trackerKey, entries: library.entries)
            importUsername = services.first { $0.key == trackerKey }?.username
            items = remote.map { entry in
                let exists =
                    linked.contains(entry.id)
                    || library.entries.contains { $0.externalID == "\(trackerKey):\(entry.id)" }
                return TrackingImportItem(
                    remote: entry, state: exists ? .existing : sourceID == nil ? .matched : .pending
                )
            }
            return true
        } catch {
            notice = "Couldn’t load your list. Check your connection and try again."
            return false
        }
    }
    static func normalized(_ value: String) -> String {
        value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    static func exactMatch(_ remote: TrackingRemoteEntry, candidates: [MediaEntry]) -> MediaEntry? {
        let names = Set(remote.names.map(normalized))
        let matches = candidates.filter { names.contains(normalized($0.title)) }
        return matches.count == 1 ? matches[0] : nil
    }
    func candidates(query: String) async throws -> [MediaEntry] {
        guard let sourceID else { return [] }
        return try await searchRepository.search(
            SearchRequest(query: query, options: SearchOptions(media: media, sourceID: sourceID)))
    }
    func matchPending(library: LibraryStore) async {
        guard !working, sourceID != nil else { return }
        working = true
        stopRequested = false
        defer {
            working = false
            persist()
        }
        for index in items.indices where items[index].state == .pending {
            if stopRequested || Task.isCancelled { break }
            do {
                let candidates = try await candidates(query: items[index].remote.title)
                if let match = Self.exactMatch(items[index].remote, candidates: candidates) {
                    items[index].match = match
                    items[index].state = library.contains(match) ? .existing : .matched
                } else {
                    items[index].state = .unmatched
                }
            } catch {
                items[index].state = .unmatched
                items[index].message = "Search failed. Choose a match to retry."
            }
            persist()
        }
    }
    func assign(_ entry: MediaEntry, to id: String, library: LibraryStore) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard
            !items.contains(where: {
                $0.id != id && $0.match?.id == entry.id && $0.state != .skipped
            })
        else {
            notice = "This source title is already matched to another item."
            return
        }
        items[index].match = entry
        items[index].state = library.contains(entry) ? .existing : .matched
        items[index].message = nil
        persist()
    }
    func skip(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .skipped
        persist()
    }
    func runImport(library: LibraryStore, dryRun: Bool) async {
        guard !working else { return }
        guard let service = services.first(where: { $0.key == trackerKey }), service.isLoggedIn,
            service.username == importUsername
        else {
            notice = "The tracking account changed. Start a new import for the connected account."
            return
        }
        if dryRun {
            notice = "\(importable.count) titles ready to import. No changes were made."
            return
        }
        working = true
        stopRequested = false
        completed = 0
        defer { working = false }
        for index in items.indices
        where items[index].state == .matched || items[index].state == .failed {
            if stopRequested || Task.isCancelled { break }
            do {
                if let match = items[index].match, library.contains(match) {
                    items[index].state = .existing
                    continue
                }
                let entry = try await repository.importTitle(
                    items[index], key: trackerKey, media: media)
                guard await library.setSaved(true, entry: entry) else {
                    throw TrackingError.message("Couldn’t save to your library. Retry the import.")
                }
                items[index].state = .imported
                items[index].message = nil
                completed += 1
            } catch {
                items[index].state = .failed
                items[index].message = "Import failed. Retry this title."
            }
            persist()
            // Bound request rate to the same service-friendly cadence used by desktop.
            do { try await Task.sleep(for: .milliseconds(800)) } catch { break }
        }
        persist()
        await flushDraft()
    }
    var failureReport: String {
        items.filter { $0.state == .failed }.map {
            "\($0.remote.title) (\($0.id)): \($0.message ?? "Import failed")"
        }.joined(separator: "\n")
    }
    func discard() {
        guard !working else { return }
        items = []
        persist()
    }
}

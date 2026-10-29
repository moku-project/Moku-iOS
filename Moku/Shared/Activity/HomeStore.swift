import Foundation
import Observation

@MainActor @Observable
final class HomeStore {
    private(set) var snapshot: HomeSnapshot {
        didSet { snapshotRevision &+= 1; cachedRecentSessions = nil }
    }
    private(set) var snapshotRevision = 0
    @ObservationIgnored private var cachedRecentSessions: [HomeSession]?
    private(set) var storageError: String?
    @ObservationIgnored private let disk: HomeDisk?
    @ObservationIgnored private var loadingTask: Task<HomeSnapshot?, Error>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var needsSave = false
    @ObservationIgnored private var pending: [(HomeStore) -> Void] = []
    private(set) var isLoaded: Bool

    init(fileURL: URL? = HomeStore.defaultURL, snapshot: HomeSnapshot = HomeSnapshot()) {
        self.snapshot = snapshot
        isLoaded = fileURL == nil
        disk = fileURL.map { HomeDisk(url: $0) }
        if let disk {
            loadingTask = Task { try await disk.read() }
            Task { [weak self] in await self?.load() }
        }
    }

    func load() async {
        guard !isLoaded, let loadingTask else { return }
        do {
            let saved = try await loadingTask.value
            guard !isLoaded else { return }
            if let saved { snapshot = saved }
        } catch {
            guard !isLoaded else { return }
            storageError = "Couldn’t load your Home activity."
        }
        isLoaded = true
        self.loadingTask = nil
        let actions = pending
        pending.removeAll()
        for action in actions { action(self) }
    }

    /// Await durable storage when a caller needs a persistence boundary.
    func flush() async {
        await load()
        await saveTask?.value
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Moku/home.json")
    }

    var recentSessions: [HomeSession] {
        // Observe the revision even when serving the cached ordering.
        _ = snapshotRevision
        if let cachedRecentSessions { return cachedRecentSessions }
        let known = Set(snapshot.entries.map(\.id))
        var latest: [String: HomeSession] = [:]
        for session in snapshot.sessions where known.contains(session.entryID) {
            if latest[session.entryID] == nil || session.endedAt > latest[session.entryID]!.endedAt {
                latest[session.entryID] = session
            }
        }
        let ordered = latest.values.sorted {
            $0.endedAt == $1.endedAt ? $0.entryID < $1.entryID : $0.endedAt > $1.endedAt
        }
        cachedRecentSessions = ordered
        return ordered
    }

    var slots: [HomeSlot] {
        let recent = recentSessions
        var next = 1
        return (0..<4).map { index in
            if index > 0, let id = snapshot.pins[index], let entry = entry(id) {
                return HomeSlot(
                    id: index, entry: entry, session: recent.first { $0.entryID == id },
                    isPinned: true)
            }
            let position = index == 0 ? 0 : next
            if index > 0 { next += 1 }
            guard recent.indices.contains(position) else { return HomeSlot(id: index) }
            let session = recent[position]
            return HomeSlot(id: index, entry: entry(session.entryID), session: session)
        }
    }

    func entry(_ id: String) -> HomeEntry? { snapshot.entries.first { $0.id == id } }

    func record(_ session: HomeSession, entry: HomeEntry) {
        guard isLoaded else {
            pending.append { $0.record(session, entry: entry) }
            return
        }
        // A reader can update the same session without inflating activity totals.
        updateEntry(entry, shouldPersist: false)
        if let index = snapshot.sessions.lastIndex(where: { $0.id == session.id }) {
            snapshot.sessions[index] = session
        } else {
            snapshot.sessions.append(session)
        }
        persist()
    }

    func pin(_ entry: HomeEntry?, slot: Int) {
        guard (1...3).contains(slot) else { return }
        guard isLoaded else {
            pending.append { $0.pin(entry, slot: slot) }
            return
        }
        if let entry {
            var saved = self.entry(entry.id) ?? entry
            saved.sourceEntry = entry.sourceEntry ?? saved.sourceEntry
            updateEntry(saved, shouldPersist: false)
        }
        snapshot.pins[slot] = entry?.id
        persist()
    }

    /// Refresh metadata without inventing reading sessions or losing source identity.
    func updateEntry(_ entry: HomeEntry, shouldPersist: Bool = true) {
        guard isLoaded else {
            pending.append { $0.updateEntry(entry, shouldPersist: shouldPersist) }
            return
        }
        var next = entry
        if let previous = self.entry(entry.id) {
            next.sourceEntry = entry.sourceEntry ?? previous.sourceEntry
            next.coverURL = entry.coverURL ?? previous.coverURL
            next.author = entry.author ?? previous.author
            next.summary = entry.summary ?? previous.summary
            if next.genres.isEmpty { next.genres = previous.genres }
        }
        if let index = snapshot.entries.firstIndex(where: { $0.id == entry.id }) {
            guard snapshot.entries[index] != next else { return }
            snapshot.entries[index] = next
        } else {
            snapshot.entries.append(next)
        }
        if shouldPersist { persist() }
    }

    func clearHistory(entryID: String? = nil) async {
        await load()
        guard storageError == nil else { return }
        if let entryID {
            snapshot.sessions.removeAll { $0.entryID == entryID }
        } else {
            snapshot.sessions = []
        }
        persist()
        await flush()
    }

    private func persist() {
        guard let disk, storageError == nil else { return }
        needsSave = true
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            // Coalesce rapid page turns, retaining at most one pending snapshot.
            try? await Task.sleep(for: .milliseconds(200))
            guard let self else { return }
            while needsSave && storageError == nil {
                needsSave = false
                let value = snapshot
                do { try await disk.write(value) }
                catch { storageError = "Couldn’t save your Home activity." }
            }
            saveTask = nil
        }
    }

    func statistics(now: Date = .now, calendar: Calendar = .current) -> HomeStatistics {
        HomeStatistics.calculate(snapshot: snapshot, now: now, calendar: calendar)
    }
}

/// Serial disk access keeps file IO and JSON coding off the main actor.

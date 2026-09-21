import Foundation
import Observation

@MainActor @Observable
final class HomeStore {
    private(set) var snapshot: HomeSnapshot
    private(set) var storageError: String?
    @ObservationIgnored private let disk: HomeDisk?
    @ObservationIgnored private var loadingTask: Task<HomeSnapshot?, Error>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
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
        var seen = Set<String>()
        let known = Set(snapshot.entries.map(\.id))
        return snapshot.sessions.sorted { $0.endedAt > $1.endedAt }.filter {
            known.contains($0.entryID) && seen.insert($0.entryID).inserted
        }
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
        snapshot.entries.removeAll { $0.id == entry.id }
        snapshot.entries.append(entry)
        snapshot.sessions.removeAll { $0.id == session.id }
        snapshot.sessions.append(session)
        persist()
    }

    func pin(_ entry: HomeEntry?, slot: Int) {
        guard (1...3).contains(slot) else { return }
        guard isLoaded else {
            pending.append { $0.pin(entry, slot: slot) }
            return
        }
        snapshot.pins[slot] = entry?.id
        persist()
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
        let value = snapshot
        let previous = saveTask
        saveTask = Task { [weak self] in
            await previous?.value
            guard self?.storageError == nil else { return }
            do {
                try await disk.write(value)
            } catch {
                self?.storageError = "Couldn’t save your Home activity."
            }
        }
    }

    func statistics(now: Date = .now, calendar: Calendar = .current) -> HomeStatistics {
        var result = HomeStatistics()
        let sessions = snapshot.sessions.filter { $0.endedAt <= now }
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today)!
        let mediaByID = Dictionary(
            snapshot.entries.map { ($0.id, $0.media) }, uniquingKeysWith: { _, latest in latest })
        for session in sessions {
            let units = max(0, session.completedUnits)
            result.units += units
            result.minutes += max(0, session.minutes)
            if session.endedAt >= weekStart { result.thisWeek += units }
            let day = calendar.startOfDay(for: session.endedAt)
            result.daily[day, default: 0] += max(1, units)
            if let media = mediaByID[session.entryID] { result.byMedia[media, default: 0] += units }
        }
        result.series = Set(sessions.map(\.entryID)).count
        result.firstRead = sessions.map(\.endedAt).min()
        result.lastRead = sessions.map(\.endedAt).max()
        if let first = result.firstRead {
            let days = max(
                1,
                (calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: today)
                    .day ?? 0) + 1)
            result.perDay = Double(result.units) / Double(days)
        }
        var previous: Date?
        var streak = 0
        for day in result.daily.keys.sorted() {
            streak =
                previous.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day
                ? streak + 1 : 1
            result.bestStreak = max(result.bestStreak, streak)
            previous = day
        }
        if let previous, previous >= calendar.date(byAdding: .day, value: -1, to: today)! {
            result.currentStreak = streak
        }
        return result
    }
}

/// Serial disk access keeps file IO and JSON coding off the main actor.

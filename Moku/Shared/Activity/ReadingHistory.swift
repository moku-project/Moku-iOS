import Foundation
import Observation

/// One stretch of reading a title, as Tsunagu stores and syncs it.
struct HistorySession: Identifiable, Equatable, Sendable {
    var id: String
    var mediaID: String
    var title: String
    var coverURL: URL?
    var media: ContentMode
    var unreadCount = 0
    var startChapterID: String?
    var endChapterID: String?
    var endChapterTitle: String?
    var startPage = 1
    var endPage = 1
    var startedAt: Date
    var endedAt: Date
    var durationMs = 0
    var chapters = 1

    var minutes: Int { durationMs / 60_000 }
}

/// What the app sends for a session; resending the same id updates it.
struct ReadingSessionInput: Equatable, Sendable {
    var id: String
    var mediaID: String
    var startChapterID: String?
    var endChapterID: String?
    var startPage: Int
    var endPage: Int
    var startedAt: Date
    var endedAt: Date
    var durationMs: Int
    var chapters: Int
}

struct ReadingDayInput: Equatable, Sendable {
    var date: String
    var seconds: Int
    var chapters: Int
}

struct ResumePoint: Equatable, Sendable {
    var chapterID: String
    var page: Int?
    var completed: Bool
    var updatedAt: Date? = nil
}

protocol ReadingHistoryRepository: Sendable {
    func sessions(limit: Int) async throws -> [HistorySession]
    func statistics(timeZone: String) async throws -> HomeStatistics
    func record(_ session: ReadingSessionInput) async throws
    func importHistory(source: String, sessions: [ReadingSessionInput], days: [ReadingDayInput])
        async throws
    func clear(mediaID: String?) async throws
    func reset() async throws
    func resumePoint(mediaID: String) async throws -> ResumePoint?
}

/// Reading history and stats from Tsunagu, which keeps them in step across paired devices.
@MainActor @Observable
final class ReadingHistory {
    private(set) var sessions: [HistorySession] = []
    private(set) var statistics = HomeStatistics()
    private(set) var isLoaded = false
    private(set) var error: String?
    private(set) var revision = 0
    /// Fresher metadata for titles Home has reloaded, keyed by media ID.
    private(set) var entries: [String: HomeEntry] = [:]
    @ObservationIgnored let repository: any ReadingHistoryRepository
    @ObservationIgnored private let legacyURL: URL?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

    init(
        repository: any ReadingHistoryRepository = LiveReadingHistoryRepository(),
        legacyURL: URL? = nil
    ) {
        self.repository = repository
        self.legacyURL = legacyURL
    }

    /// Latest session per title, newest first.
    var recent: [HistorySession] {
        var seen = Set<String>()
        return sessions.filter { seen.insert($0.mediaID).inserted }
    }

    var lastRead: [String: Date] {
        sessions.reduce(into: [:]) { result, session in
            result[session.mediaID] = max(result[session.mediaID] ?? .distantPast, session.endedAt)
        }
    }

    func load() async {
        if isLoaded { return }
        await refresh()
    }

    func refresh() async {
        if let loading { return await loading.value }
        let task = Task {
            if let legacyURL { await LegacyHistoryImport.run(from: legacyURL, into: repository) }
            do {
                async let sessions = repository.sessions(limit: 500)
                async let statistics = repository.statistics(timeZone: TimeZone.current.identifier)
                let (loadedSessions, loadedStatistics) = try await (sessions, statistics)
                self.sessions = loadedSessions
                self.statistics = loadedStatistics
                error = nil
            } catch {
                self.error = "Couldn’t load your reading history."
            }
            isLoaded = true
            revision &+= 1
        }
        loading = task
        await task.value
        loading = nil
    }

    func record(_ session: ReadingSessionInput) async {
        do {
            try await repository.record(session)
            scheduleRefresh()
        } catch {
            // The recorder resends the whole session on its next update.
        }
    }

    func clear(mediaID: String? = nil) async {
        do {
            try await repository.clear(mediaID: mediaID)
            await refresh()
        } catch {
            self.error = "Couldn’t clear reading history."
        }
    }

    func reset() async {
        do {
            try await repository.reset()
            await refresh()
        } catch {
            self.error = "Couldn’t reset reading stats."
        }
    }

    func update(_ entry: HomeEntry) {
        guard entries[entry.id] != entry else { return }
        entries[entry.id] = entry
        revision &+= 1
    }

    /// The title as Home shows it: session metadata, overlaid with anything reloaded since.
    func entry(for session: HistorySession) -> HomeEntry {
        var entry =
            entries[session.mediaID]
            ?? HomeEntry(
                id: session.mediaID, title: session.title, coverURL: session.coverURL,
                media: session.media.title, unreadCount: session.unreadCount)
        if entry.coverURL == nil { entry.coverURL = session.coverURL }
        return entry
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }
}

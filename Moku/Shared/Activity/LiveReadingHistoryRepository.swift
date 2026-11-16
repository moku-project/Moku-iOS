import Foundation

struct LiveReadingHistoryRepository: ReadingHistoryRepository {
    private struct Session: Decodable, Sendable {
        struct Media: Decodable, Sendable {
            let id: String
            let title: String
            let thumbnailUrl: String?
            let contentType: String
            let unreadCount: Int
        }
        struct ChapterRef: Decodable, Sendable {
            let id: String
            let title: String?
            let number: Double?
        }
        let id: String
        let media: Media
        let startChapter: ChapterRef?
        let endChapter: ChapterRef?
        let startPage: Int
        let endPage: Int
        let startedAt: String
        let endedAt: String
        let durationMs: Int
        let chapters: Int
    }

    private static let sessionFields = """
        id media { id title thumbnailUrl contentType unreadCount } startChapter { id } \
        endChapter { id title number } startPage endPage startedAt endedAt durationMs chapters
        """

    func sessions(limit: Int) async throws -> [HistorySession] {
        struct Response: Decodable, Sendable { let readingSessions: [Session] }
        let response: Response = try await BackendAPI.shared.graphql(
            "{ readingSessions(limit: \(limit)) { \(Self.sessionFields) } }",
            requiresSourceRuntime: false)
        return response.readingSessions.compactMap { session in
            guard let started = ChapterSync.date(session.startedAt),
                let ended = ChapterSync.date(session.endedAt)
            else { return nil }
            let chapter = session.endChapter.map {
                Chapter(
                    id: $0.id, title: $0.title, number: $0.number, scanlator: nil, completed: false,
                    downloaded: false
                ).label
            }
            return HistorySession(
                id: session.id, mediaID: session.media.id, title: session.media.title,
                coverURL: BackendAPI.coverURL(session.media.thumbnailUrl),
                media: ContentMode(
                    rawValue: session.media.contentType.lowercased() == "novel"
                        ? "novels" : session.media.contentType.lowercased()) ?? .manga,
                unreadCount: session.media.unreadCount,
                startChapterID: session.startChapter?.id, endChapterID: session.endChapter?.id,
                endChapterTitle: chapter, startPage: session.startPage, endPage: session.endPage,
                startedAt: started, endedAt: ended, durationMs: session.durationMs,
                chapters: session.chapters)
        }
    }

    func statistics(timeZone: String) async throws -> HomeStatistics {
        struct Response: Decodable, Sendable {
            struct Stats: Decodable, Sendable {
                struct Day: Decodable, Sendable {
                    let date: String
                    let chapters: Int
                }
                let totalChaptersRead: Int
                let totalTitlesRead: Int
                let totalMinutesRead: Int
                let chaptersThisWeek: Int
                let firstReadAt: String?
                let lastReadAt: String?
                let currentStreakDays: Int
                let longestStreakDays: Int
                let days: [Day]
            }
            let readingStats: Stats
        }
        let response: Response = try await BackendAPI.shared.graphql(
            """
            { readingStats(timeZone: \(BackendAPI.literal(timeZone))) { totalChaptersRead totalTitlesRead \
            totalMinutesRead chaptersThisWeek firstReadAt lastReadAt currentStreakDays longestStreakDays \
            days { date chapters } } }
            """, requiresSourceRuntime: false)
        let stats = response.readingStats
        var result = HomeStatistics(
            units: stats.totalChaptersRead, minutes: stats.totalMinutesRead,
            thisWeek: stats.chaptersThisWeek,
            series: stats.totalTitlesRead, currentStreak: stats.currentStreakDays,
            bestStreak: stats.longestStreakDays, firstRead: ChapterSync.date(stats.firstReadAt),
            lastRead: ChapterSync.date(stats.lastReadAt))
        for day in stats.days {
            if let date = Self.day(day.date) { result.daily[date, default: 0] += day.chapters }
        }
        if let first = result.firstRead {
            result.perDay =
                Double(result.units)
                / Double(max(1, Int(ceil(Date.now.timeIntervalSince(first) / 86_400))))
        }
        return result
    }

    func record(_ session: ReadingSessionInput) async throws {
        let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
            "mutation { recordReadingSession(input: \(Self.literal(session))) { id } }",
            requiresSourceRuntime: false)
    }

    func importHistory(source: String, sessions: [ReadingSessionInput], days: [ReadingDayInput])
        async throws
    {
        let sessionList = sessions.map(Self.literal).joined(separator: ",")
        let dayList = days.map {
            "{date: \(BackendAPI.literal($0.date)), seconds: \($0.seconds), chapters: \($0.chapters)}"
        }.joined(separator: ",")
        let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
            """
            mutation { importReadingHistory(source: \(BackendAPI.literal(source)), \
            sessions: [\(sessionList)], days: [\(dayList)]) { imported } }
            """, requiresSourceRuntime: false)
    }

    func clear(mediaID: String?) async throws {
        let argument = mediaID.map { "(mediaId: \(BackendAPI.literal($0)))" } ?? ""
        let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
            "mutation { clearReadingHistory\(argument) }", requiresSourceRuntime: false)
    }

    func reset() async throws {
        let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
            "mutation { resetReadingStats }", requiresSourceRuntime: false)
    }

    func resumePoint(mediaID: String) async throws -> ResumePoint? {
        struct Response: Decodable, Sendable {
            struct Media: Decodable, Sendable {
                struct Point: Decodable, Sendable {
                    let chapterId: String
                    let page: Int?
                    let completed: Bool
                    let updatedAt: String?
                }
                let resumePoint: Point?
            }
            let media: Media?
        }
        let response: Response = try await BackendAPI.shared.graphql(
            "{ media(id: \(BackendAPI.literal(mediaID))) { resumePoint { chapterId page completed updatedAt } } }",
            requiresSourceRuntime: false)
        return response.media?.resumePoint.map {
            ResumePoint(
                chapterID: $0.chapterId, page: $0.page, completed: $0.completed,
                updatedAt: ChapterSync.date($0.updatedAt))
        }
    }

    private static func literal(_ session: ReadingSessionInput) -> String {
        var fields = [
            "id: \(BackendAPI.literal(session.id))",
            "mediaId: \(BackendAPI.literal(session.mediaID))",
            "startPage: \(session.startPage)", "endPage: \(session.endPage)",
            "startedAt: \(BackendAPI.literal(time(session.startedAt)))",
            "endedAt: \(BackendAPI.literal(time(session.endedAt)))",
            "durationMs: \(session.durationMs)", "chapters: \(session.chapters)",
        ]
        if let id = session.startChapterID {
            fields.append("startChapterId: \(BackendAPI.literal(id))")
        }
        if let id = session.endChapterID {
            fields.append("endChapterId: \(BackendAPI.literal(id))")
        }
        return "{" + fields.joined(separator: ", ") + "}"
    }

    private static func time(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func day(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

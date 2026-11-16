#if DEBUG
    import Foundation
    import SwiftUI

    enum HomePreviewData {
        static let entries = [
            HomeEntry(
                id: "talent", title: "I’m Not That Kind of Talent",
                genres: ["Action", "Fantasy"], unreadCount: 117,
                chapters: (11...15).map { HomeChapter(id: "\($0)", title: "Chapter \($0)") },
                summary: "A reluctant hero is mistaken for a formidable warrior. As rumors of his talent spread, he must navigate a world of rival factions, unexpected allies, and increasingly dangerous adventures."),
            HomeEntry(
                id: "wild", title: "Monster But Wild", media: "Anime", unreadCount: 4,
                chapters: [HomeChapter(id: "8", title: "Episode 8")]),
            HomeEntry(
                id: "overgeared", title: "Overgeared", media: "Novels",
                chapters: [HomeChapter(id: "31", title: "Chapter 31")]),
        ]

        @MainActor static func makeStore(titleCount: Int = 3) -> ReadingHistory {
            let history = ReadingHistory(
                repository: PreviewReadingHistoryRepository(sessions: sessions(titleCount: titleCount)))
            for var entry in entries {
                entry.sourceEntry = MediaEntry(
                    id: entry.id, title: entry.title,
                    media: entry.media == "Anime" ? .anime : entry.media == "Novels" ? .novels : .manga,
                    sourceName: "Preview source", coverURL: nil, extensionID: "preview", externalID: entry.id)
                history.update(entry)
            }
            return history
        }

        static func entry(_ id: String) -> HomeEntry? { entries.first { $0.id == id } }

        static func sessions(titleCount: Int) -> [HistorySession] {
            guard titleCount > 0 else { return [] }
            return (0..<12).filter { $0 != 5 && $0 != 9 }.map { day in
                let entry = entries[day % min(titleCount, entries.count)]
                let ended = Calendar.current.date(byAdding: .day, value: -day, to: .now)!
                return HistorySession(
                    id: "preview-\(day)", mediaID: entry.id, title: entry.title, coverURL: nil,
                    media: entry.media == "Anime" ? .anime : entry.media == "Novels" ? .novels : .manga,
                    unreadCount: entry.unreadCount, startChapterID: entry.chapters[0].id,
                    endChapterID: entry.chapters[0].id, endChapterTitle: entry.chapters[0].title,
                    endPage: day == 0 ? 37 : 1, startedAt: ended.addingTimeInterval(-2520), endedAt: ended,
                    durationMs: 2_520_000, chapters: 3)
            }
        }
    }

    /// In-memory history for previews and UI tests.
    actor PreviewReadingHistoryRepository: ReadingHistoryRepository {
        private var stored: [HistorySession]
        init(sessions: [HistorySession]) { stored = sessions }

        func sessions(limit: Int) async throws -> [HistorySession] {
            Array(stored.sorted { $0.endedAt > $1.endedAt }.prefix(limit))
        }
        func statistics(timeZone: String) async throws -> HomeStatistics {
            let calendar = Calendar.current
            var result = HomeStatistics(
                units: stored.reduce(0) { $0 + $1.chapters }, minutes: stored.reduce(0) { $0 + $1.minutes },
                series: Set(stored.map(\.mediaID)).count,
                firstRead: stored.map(\.startedAt).min(), lastRead: stored.map(\.endedAt).max())
            for session in stored {
                result.daily[calendar.startOfDay(for: session.endedAt), default: 0] += session.chapters
                if session.endedAt > .now.addingTimeInterval(-7 * 86_400) { result.thisWeek += session.chapters }
            }
            var day = calendar.startOfDay(for: .now)
            if result.daily[day] == nil { day = calendar.date(byAdding: .day, value: -1, to: day)! }
            while result.daily[day] != nil {
                result.currentStreak += 1
                day = calendar.date(byAdding: .day, value: -1, to: day)!
            }
            result.bestStreak = result.currentStreak
            return result
        }
        func record(_ session: ReadingSessionInput) async throws {}
        func importHistory(source: String, sessions: [ReadingSessionInput], days: [ReadingDayInput]) async throws {}
        func clear(mediaID: String?) async throws { stored.removeAll { mediaID == nil || $0.mediaID == mediaID } }
        func reset() async throws { stored = [] }
        func resumePoint(mediaID: String) async throws -> ResumePoint? {
            stored.first { $0.mediaID == mediaID }.flatMap { session in
                session.endChapterID.map { ResumePoint(chapterID: $0, page: session.endPage, completed: false) }
            }
        }
    }

    struct HomePreviewDetailsRepository: DetailsRepository {
        func metadata(for entry: MediaEntry, refresh: Bool) async throws -> MediaDetails {
            let saved = HomePreviewData.entry(entry.id)
            return MediaDetails(
                id: entry.id, title: entry.title, thumbnailUrl: nil,
                description: saved?.summary, author: nil, artist: nil, status: nil,
                genres: saved?.genres ?? [], inLibrary: true, chapters: [])
        }
        func chapters(mediaID: String) async throws -> [Chapter] {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-home-large-chapters") {
                // A long list checks Home stays responsive when a title has thousands of chapters.
                return (1...2_000).map { index in
                    Chapter(id: "large-\(index)", title: "Chapter \(index)", number: Double(index),
                            scanlator: "Preview group", completed: false, downloaded: false,
                            sourceOrder: index)
                }
            }
            let saved = HomePreviewData.entry(mediaID)
            return (saved?.chapters ?? []).enumerated().map { index, chapter in
                Chapter(id: chapter.id, title: chapter.title, number: Double(index),
                        scanlator: "Preview group", completed: chapter.isRead, downloaded: false,
                        sourceOrder: index)
            }
        }
    }
#endif

#if DEBUG
    import Foundation
    import SwiftUI

    enum HomePreviewData {
        @MainActor static func makeStore(titleCount: Int = 3) -> HomeStore {
            let store = HomeStore(fileURL: nil)
            let entries = [
                HomeEntry(
                    id: "talent", title: "I’m Not That Kind of Talent",
                    genres: ["Action", "Fantasy"], unreadCount: 117,
                    chapters: (11...15).map { HomeChapter(id: "\($0)", title: "Chapter \($0)") },
                    summary: "A reluctant hero is mistaken for a formidable warrior. As rumors of his talent spread, he must navigate a world of rival factions, unexpected allies, and increasingly dangerous adventures."),
                HomeEntry(
                    id: "wild", title: "Monster But Wild", media: "Anime",
                    chapters: [HomeChapter(id: "8", title: "Episode 8")]),
                HomeEntry(
                    id: "overgeared", title: "Overgeared", media: "Novels",
                    chapters: [HomeChapter(id: "31", title: "Chapter 31")]),
            ]
            for day in (0..<12).reversed() where day != 5 && day != 9 {
                var entry = entries[day % max(1, min(titleCount, entries.count))]
                entry.sourceEntry = MediaEntry(
                    id: entry.id, title: entry.title,
                    media: entry.media == "Anime" ? .anime : entry.media == "Novels" ? .novels : .manga,
                    sourceName: "Preview source", coverURL: nil, extensionID: "preview", externalID: entry.id)
                store.record(
                    HomeSession(
                        entryID: entry.id, chapterID: entry.chapters[0].id, page: day == 0 ? 37 : 1,
                        endedAt: Calendar.current.date(byAdding: .day, value: -day, to: .now)!,
                        minutes: 42, completedUnits: 3), entry: entry)
            }
            return store
        }
    }

    struct HomePreviewDetailsRepository: DetailsRepository {
        func metadata(for entry: MediaEntry, refresh: Bool) async throws -> MediaDetails {
            let saved = await MainActor.run { HomePreviewData.makeStore().entry(entry.id) }
            return MediaDetails(
                id: entry.id, title: entry.title, thumbnailUrl: nil,
                description: saved?.summary, author: nil, artist: nil, status: nil,
                genres: saved?.genres ?? [], inLibrary: true, chapters: [])
        }
        func chapters(mediaID: String) async throws -> [Chapter] {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-home-large-chapters") {
                // A missing resume ID forces Up next to scan the entire loaded list.
                return (1...2_000).map { index in
                    Chapter(id: "large-\(index)", title: "Chapter \(index)", number: Double(index),
                            scanlator: "Preview group", completed: false, downloaded: false,
                            sourceOrder: index)
                }
            }
            let saved = await MainActor.run { HomePreviewData.makeStore().entry(mediaID) }
            return (saved?.chapters ?? []).enumerated().map { index, chapter in
                Chapter(id: chapter.id, title: chapter.title, number: Double(index),
                        scanlator: "Preview group", completed: chapter.isRead, downloaded: false,
                        sourceOrder: index)
            }
        }
    }
#endif

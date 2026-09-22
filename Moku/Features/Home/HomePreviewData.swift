#if DEBUG
    import Foundation
    import SwiftUI

    enum HomePreviewData {
        @MainActor static func makeStore() -> HomeStore {
            let store = HomeStore(fileURL: nil)
            let entries = [
                HomeEntry(
                    id: "talent", title: "I’m Not That Kind of Talent",
                    genres: ["Action", "Fantasy"], unreadCount: 117,
                    chapters: (11...15).map { HomeChapter(id: "\($0)", title: "Chapter \($0)") }),
                HomeEntry(
                    id: "wild", title: "Monster But Wild", media: "Anime",
                    chapters: [HomeChapter(id: "8", title: "Episode 8")]),
                HomeEntry(
                    id: "overgeared", title: "Overgeared", media: "Novels",
                    chapters: [HomeChapter(id: "31", title: "Chapter 31")]),
            ]
            for day in (0..<12).reversed() where day != 5 && day != 9 {
                let entry = entries[day % 3]
                store.record(
                    HomeSession(
                        entryID: entry.id, chapterID: entry.chapters[0].id, page: day == 0 ? 37 : 1,
                        endedAt: Calendar.current.date(byAdding: .day, value: -day, to: .now)!,
                        minutes: 42, completedUnits: 3), entry: entry)
            }
            return store
        }
    }

#endif

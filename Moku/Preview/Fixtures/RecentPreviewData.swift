#if DEBUG
    import SwiftUI

    enum RecentPreviewData {
        static let entries = [
            MediaEntry(
                id: "talent", title: "I’m Not That Kind of Talent", media: .manga,
                sourceName: "Preview",
                coverURL: nil),
            MediaEntry(
                id: "wild", title: "Monster But Wild", media: .anime, sourceName: "Preview",
                coverURL: nil),
        ]
        struct Repository: RecentRepository {
            func chapters(for entry: MediaEntry, refresh: Bool) async throws -> [RecentUpdate] {
                let end = entry.media == .manga ? 14 : 12
                let prefix = entry.media == .anime ? "Episode" : "Chapter"
                let date = ISO8601DateFormatter().string(from: Date())
                return (11...end).map { number in
                    let chapter = RecentChapter(
                        id: String(number), title: "\(prefix) \(number)",
                        number: Double(number), uploadedAt: date,
                        completed: number == 11, downloaded: number == 12)
                    return RecentUpdate(entry: entry, mediaID: entry.id, chapter: chapter)
                }
            }
            func entry(id: String) throws -> MediaEntry {
                guard let entry = entries.first(where: { $0.id == id }) else {
                    throw SearchFailure.notConnected
                }
                return entry
            }
            func download(_ update: RecentUpdate, delete: Bool) async throws {}
        }
    }
#endif

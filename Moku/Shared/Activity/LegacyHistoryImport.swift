import Foundation

/// Sends the history older versions kept in home.json to Tsunagu once, then deletes the file.
enum LegacyHistoryImport {
    private struct Snapshot: Decodable {
        struct Session: Decodable {
            let id: UUID
            let entryID: String
            let chapterID: String
            let page: Int
            let endedAt: Date
            let minutes: Int
            let completedUnits: Int
            let startedAt: Date?
            let durationSeconds: Double?
        }
        let sessions: [Session]
    }

    private static let sourceKey = "history.importSource"

    static func run(from url: URL, into repository: any ReadingHistoryRepository) async {
        guard FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        let (sessions, days) = convert(
            snapshot.sessions.map {
                (
                    $0.id, $0.entryID, $0.chapterID, $0.page, $0.endedAt, $0.minutes,
                    $0.completedUnits,
                    $0.startedAt, $0.durationSeconds
                )
            })
        do {
            try await repository.importHistory(source: source, sessions: sessions, days: days)
            try? FileManager.default.removeItem(at: url)
        } catch {
            // Tried again on the next launch; the source id keeps a retry from doubling days.
        }
    }

    /// Server IDs only: sessions for titles Tsunagu never knew can't be matched.
    static func convert(
        _ sessions: [(UUID, String, String, Int, Date, Int, Int, Date?, Double?)],
        calendar: Calendar = .current
    ) -> ([ReadingSessionInput], [ReadingDayInput]) {
        var inputs: [ReadingSessionInput] = []
        var days: [String: (seconds: Double, chapters: Int)] = [:]
        for (id, entryID, chapterID, page, endedAt, minutes, units, startedAt, durationSeconds)
            in sessions
        {
            let seconds = min(3600, max(0, durationSeconds ?? Double(minutes * 60)))
            let parts = calendar.dateComponents([.year, .month, .day], from: endedAt)
            let key = String(
                format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            days[key, default: (0, 0)].seconds += seconds
            days[key, default: (0, 0)].chapters += max(1, units)
            guard Int64(entryID) != nil else { continue }
            let chapter = Int64(chapterID) != nil ? chapterID : nil
            inputs.append(
                ReadingSessionInput(
                    id: id.uuidString, mediaID: entryID, startChapterID: chapter,
                    endChapterID: chapter,
                    startPage: max(1, page), endPage: max(1, page),
                    startedAt: startedAt ?? endedAt.addingTimeInterval(-seconds), endedAt: endedAt,
                    durationMs: Int(seconds * 1000), chapters: 1))
        }
        let dayInputs = days.keys.sorted().map {
            ReadingDayInput(date: $0, seconds: Int(days[$0]!.seconds), chapters: days[$0]!.chapters)
        }
        return (inputs, dayInputs)
    }

    private static var source: String {
        if let saved = UserDefaults.standard.string(forKey: sourceKey) { return saved }
        let made = "moku-ios-" + UUID().uuidString
        UserDefaults.standard.set(made, forKey: sourceKey)
        return made
    }
}

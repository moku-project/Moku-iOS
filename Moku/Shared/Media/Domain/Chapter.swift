import Foundation

struct Chapter: Decodable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String?
    let number: Double?
    let scanlator: String?
    var completed: Bool
    var downloaded: Bool
    var uploadedAt: String? = nil
    var sourceOrder: Int? = nil
    /// Where reading or watching stopped; nil when the chapter was never opened.
    var readingProgress: Progress? = nil
    struct Progress: Decodable, Sendable, Equatable {
        let progress: Double
        var positionSeconds: Double? = nil
    }
    var label: String { title ?? number.map { "Chapter \($0.formatted())" } ?? "Chapter" }
    var uploadedDate: String? {
        guard let uploadedAt, let date = Self.parse(uploadedAt) else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func parse(_ value: String) -> Date? {
        if let date = try? Date(value, strategy: .iso8601) { return date }
        return try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}

/// Shared by Home and Details so a title keeps the same release selection.
struct ChapterDisplayPreferences: Codable, Equatable {
    var preferred = ""
    var included: [String] = []
    var excluded: [String] = []
    var onlyIncluded = false

    static func read(_ data: Data, id: String) -> Self {
        (try? JSONDecoder().decode([String: Self].self, from: data))?[id] ?? Self()
    }

    func apply(_ chapters: [Chapter]) -> [Chapter] {
        func ordered(_ lhs: Chapter, _ rhs: Chapter) -> Bool {
            if lhs.sourceOrder != rhs.sourceOrder {
                return (lhs.sourceOrder ?? 0) < (rhs.sourceOrder ?? 0)
            }
            return (lhs.number ?? -1) < (rhs.number ?? -1)
        }
        var list = chapters.filter { !excluded.contains($0.scanlator ?? "") }.sorted(by: ordered)
        if !preferred.isEmpty {
            list = list.filter { $0.scanlator == preferred } + list.filter { $0.scanlator != preferred }
        }
        guard !included.isEmpty else { return list }
        var numbered: [Double: Chapter] = [:]
        var unnumbered: [Chapter] = []
        for chapter in list {
            let priority = included.firstIndex(of: chapter.scanlator ?? "")
            guard !onlyIncluded || priority != nil else { continue }
            guard let number = chapter.number, number >= 0 else {
                unnumbered.append(chapter)
                continue
            }
            if let existing = numbered[number] {
                let previous = included.firstIndex(of: existing.scanlator ?? "")
                if let priority, previous == nil || priority < previous! { numbered[number] = chapter }
            } else { numbered[number] = chapter }
        }
        return (Array(numbered.values) + unnumbered).sorted(by: ordered)
    }
}

/// Desktop SeriesActions sort modes.
enum ChapterSort: String, CaseIterable, Identifiable, Sendable {
    case number, source, uploaded
    var id: Self { self }
    var title: String {
        switch self {
        case .number: "Chapter number"
        case .source: "Source order"
        case .uploaded: "Upload date"
        }
    }
}

/// Pure list preparation runs outside SwiftUI's rendering transaction.
enum ChapterPresentation {
    nonisolated static func filtered(
        _ chapters: [Chapter], preferences: Data, mediaID: String, query: String, ascending: Bool,
        sort: ChapterSort = .number
    ) async -> [Chapter] {
        let list = ChapterDisplayPreferences.read(preferences, id: mediaID).apply(chapters).filter {
            query.isEmpty || $0.label.localizedCaseInsensitiveContains(query)
        }
        // Stable sorting preserves the preferred release group for equal keys.
        switch sort {
        case .number:
            return list.sorted {
                ascending ? ($0.number ?? 0) < ($1.number ?? 0) : ($0.number ?? 0) > ($1.number ?? 0)
            }
        case .source:
            // Sources list newest first, so ascending (oldest first) is the reverse.
            return list.sorted {
                ascending ? ($0.sourceOrder ?? 0) > ($1.sourceOrder ?? 0) : ($0.sourceOrder ?? 0) < ($1.sourceOrder ?? 0)
            }
        case .uploaded:
            return list.sorted {
                ascending ? ($0.uploadedAt ?? "") < ($1.uploadedAt ?? "") : ($0.uploadedAt ?? "") > ($1.uploadedAt ?? "")
            }
        }
    }

    /// Reading order is oldest first by chapter number, after release-group preferences.
    nonisolated static func readingOrder(_ chapters: [Chapter], preferences: Data, mediaID: String) -> [Chapter] {
        ChapterDisplayPreferences.read(preferences, id: mediaID).apply(chapters)
            .sorted { ($0.number ?? 0) < ($1.number ?? 0) }
    }
}

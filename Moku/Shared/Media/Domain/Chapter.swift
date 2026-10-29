import Foundation

struct Chapter: Decodable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String?
    let number: Double?
    let scanlator: String?
    let completed: Bool
    let downloaded: Bool
    var uploadedAt: String? = nil
    var sourceOrder: Int? = nil
    var label: String { title ?? number.map { "Chapter \($0.formatted())" } ?? "Chapter" }
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

/// Pure list preparation runs outside SwiftUI's rendering transaction.
enum ChapterPresentation {
    nonisolated static func filtered(
        _ chapters: [Chapter], preferences: Data, mediaID: String, query: String, ascending: Bool
    ) async -> [Chapter] {
        ChapterDisplayPreferences.read(preferences, id: mediaID).apply(chapters).filter {
            query.isEmpty || $0.label.localizedCaseInsensitiveContains(query)
        }.sorted {
            // Stable sorting preserves the preferred release group for equal numbers.
            return ascending ? ($0.number ?? 0) < ($1.number ?? 0) : ($0.number ?? 0) > ($1.number ?? 0)
        }
    }
}

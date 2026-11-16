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
    /// Bookmarked by the reader, as in Mihon.
    var bookmarked = false
    /// The latest download job for this chapter; nil when it was never queued.
    var download: DownloadJob? = nil
    struct DownloadJob: Decodable, Sendable, Equatable {
        enum Status: String, Decodable, Sendable {
            case queued = "QUEUED"
            case downloading = "DOWNLOADING"
            case done = "DONE"
            case failed = "FAILED"
        }
        var status: Status
        var progress: Double = 0
    }

    /// A finished job counts only while its files exist, so a deleted download reads as not downloaded.
    enum DownloadState: Equatable, Sendable {
        case none, queued
        case downloading(Double)
        case failed, downloaded
    }
    var downloadState: DownloadState {
        if downloaded { return .downloaded }
        switch download?.status {
        case .queued: return .queued
        case .downloading: return .downloading(min(1, max(0, download?.progress ?? 0)))
        case .failed: return .failed
        default: return .none
        }
    }
    /// Queued or downloading, so the page keeps polling for updates.
    var isDownloadActive: Bool {
        switch downloadState {
        case .queued, .downloading: true
        default: false
        }
    }
    /// Not downloaded and not already in the queue.
    var canQueueDownload: Bool { !downloaded && !isDownloadActive }
    /// Partial progress (0 < progress < 1) for an unfinished chapter, else nil.
    var partialProgress: Double? {
        guard !completed, let value = readingProgress?.progress, value > 0.01, value < 0.99 else {
            return nil
        }
        return value
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

// Queries that don't ask for bookmarks or download jobs still decode.
extension Chapter {
    private enum CodingKeys: String, CodingKey {
        case id, title, number, scanlator, completed, downloaded, uploadedAt, sourceOrder,
            readingProgress, bookmarked, download
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        number = try values.decodeIfPresent(Double.self, forKey: .number)
        scanlator = try values.decodeIfPresent(String.self, forKey: .scanlator)
        completed = try values.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        downloaded = try values.decodeIfPresent(Bool.self, forKey: .downloaded) ?? false
        uploadedAt = try values.decodeIfPresent(String.self, forKey: .uploadedAt)
        sourceOrder = try values.decodeIfPresent(Int.self, forKey: .sourceOrder)
        readingProgress = try values.decodeIfPresent(Progress.self, forKey: .readingProgress)
        bookmarked = try values.decodeIfPresent(Bool.self, forKey: .bookmarked) ?? false
        // An unknown future status shouldn't fail the whole chapter list.
        download = try? values.decodeIfPresent(DownloadJob.self, forKey: .download)
    }
}

/// Chapter list filter: All / Unread / Downloaded / Bookmarked.
enum ChapterStateFilter: String, CaseIterable, Identifiable, Sendable {
    case all, unread, downloaded, bookmarked
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        case .downloaded: "Downloaded"
        case .bookmarked: "Bookmarked"
        }
    }
    var symbol: String {
        switch self {
        case .all: "list.bullet"
        case .unread: "circle"
        case .downloaded: "arrow.down.circle"
        case .bookmarked: "bookmark"
        }
    }
    nonisolated func includes(_ chapter: Chapter) -> Bool {
        switch self {
        case .all: true
        case .unread: !chapter.completed
        case .downloaded: chapter.downloaded
        case .bookmarked: chapter.bookmarked
        }
    }

    /// Kept per title beside the release-group preferences.
    static func read(_ data: Data, id: String) -> Self {
        ((try? JSONDecoder().decode([String: String].self, from: data))?[id]).flatMap(Self.init)
            ?? .all
    }
    func write(into data: Data, id: String) -> Data {
        var all = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        all[id] = self == .all ? nil : rawValue
        return (try? JSONEncoder().encode(all)) ?? data
    }
}

/// Shared by Home and Details so a title keeps the same release selection.
struct ChapterDisplayPreferences: Codable, Equatable {
    var preferred = ""
    var included: [String] = []
    var excluded: [String] = []
    /// Unused since Show Only always filters; kept so saved preferences still decode.
    var onlyIncluded = false
    /// "Hide duplicate chapters": one chapter per number, preferring the chosen group.
    var hideDuplicates = false

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
        let list = chapters.filter {
            let group = $0.scanlator ?? ""
            return !excluded.contains(group) && (included.isEmpty || included.contains(group))
        }.sorted(by: ordered)
        guard hideDuplicates else { return list }
        // One chapter per number; the preferred group's release wins.
        let chosen = Self.unique(
            list.filter { $0.scanlator == preferred } + list.filter { $0.scanlator != preferred })
        return chosen.sorted(by: ordered)
    }

    /// Keeps the first chapter seen for each number; unnumbered chapters all stay.
    private static func unique(_ chapters: [Chapter]) -> [Chapter] {
        var seen = Set<Double>()
        return chapters.filter { chapter in
            guard let number = chapter.number, number >= 0 else { return true }
            return seen.insert(number).inserted
        }
    }
}

// Older saved preferences lack newer keys, so each one decodes with its default.
extension ChapterDisplayPreferences {
    private enum CodingKeys: String, CodingKey {
        case preferred, included, excluded, onlyIncluded, hideDuplicates
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        preferred = try values.decodeIfPresent(String.self, forKey: .preferred) ?? ""
        included = try values.decodeIfPresent([String].self, forKey: .included) ?? []
        excluded = try values.decodeIfPresent([String].self, forKey: .excluded) ?? []
        onlyIncluded = try values.decodeIfPresent(Bool.self, forKey: .onlyIncluded) ?? false
        hideDuplicates = try values.decodeIfPresent(Bool.self, forKey: .hideDuplicates) ?? false
    }
}

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
        sort: ChapterSort = .number, state: ChapterStateFilter = .all
    ) async -> [Chapter] {
        let list = ChapterDisplayPreferences.read(preferences, id: mediaID).apply(chapters).filter {
            state.includes($0)
                && (query.isEmpty || $0.label.localizedCaseInsensitiveContains(query))
        }
        // Stable sorting preserves the preferred release group for equal keys.
        switch sort {
        case .number:
            return list.sorted {
                ascending
                    ? ($0.number ?? 0) < ($1.number ?? 0) : ($0.number ?? 0) > ($1.number ?? 0)
            }
        case .source:
            // Sources list newest first, so ascending (oldest first) is the reverse.
            return list.sorted {
                ascending
                    ? ($0.sourceOrder ?? 0) > ($1.sourceOrder ?? 0)
                    : ($0.sourceOrder ?? 0) < ($1.sourceOrder ?? 0)
            }
        case .uploaded:
            return list.sorted {
                ascending
                    ? ($0.uploadedAt ?? "") < ($1.uploadedAt ?? "")
                    : ($0.uploadedAt ?? "") > ($1.uploadedAt ?? "")
            }
        }
    }

    /// Reading order is oldest first by chapter number, after release-group preferences.
    nonisolated static func readingOrder(_ chapters: [Chapter], preferences: Data, mediaID: String)
        -> [Chapter]
    {
        ChapterDisplayPreferences.read(preferences, id: mediaID).apply(chapters)
            .sorted { ($0.number ?? 0) < ($1.number ?? 0) }
    }
}

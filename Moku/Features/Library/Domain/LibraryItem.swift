import Foundation

enum LibraryTab: String, CaseIterable, Identifiable {
    case saved = "Saved"
    case downloaded = "Downloaded"
    case starred = "Starred"
    case reading = "Reading"
    case completed = "Completed"
    var id: Self { self }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case title = "A–Z"
    case unread = "Unread chapters"
    case total = "Total chapters"
    case added = "Recently added"
    case read = "Recently read"
    case uploaded = "Latest upload"
    var id: Self { self }
}

enum LibraryStatus: String, CaseIterable, Identifiable {
    case ongoing = "Ongoing"
    case completed = "Completed"
    case hiatus = "Hiatus"
    case cancelled = "Cancelled"
    case finished = "Publishing finished"
    var id: Self { self }

    /// Source status strings vary ("ONGOING", "on_hiatus", "Publishing finished").
    init?(source value: String?) {
        guard let value = value?.lowercased().replacingOccurrences(of: "_", with: " ") else { return nil }
        if value.contains("hiatus") { self = .hiatus }
        else if value.contains("cancel") || value.contains("abandon") { self = .cancelled }
        else if value.contains("publishing finished") || value.contains("finished") { self = .finished }
        else if value.contains("complete") { self = .completed }
        else if value.contains("ongoing") || value.contains("publishing") { self = .ongoing }
        else { return nil }
    }
}

struct LibraryItem: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let media: ContentMode
    var coverURL: URL?
    var readUnits = 0
    var totalUnits = 0
    var downloaded = false
    var bookmarked = false
    var status: LibraryStatus?
    var addedAt = Date.distantPast
    var latestUpload = Date.distantPast
    var tracked = false
    var lastRead = Date.distantPast
    var hasStarted: Bool { readUnits > 0 || lastRead > .distantPast }
    var unread: Int { max(0, totalUnits - readUnits) }
    var isCompleted: Bool { totalUnits > 0 && readUnits >= totalUnits }
}

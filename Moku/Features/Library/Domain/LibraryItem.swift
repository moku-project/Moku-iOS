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
    var id: Self { self }
}

enum LibraryStatus: String, CaseIterable, Identifiable {
    case ongoing = "Ongoing"
    case completed = "Completed"
    case hiatus = "Hiatus"
    case cancelled = "Cancelled"
    case finished = "Publishing finished"
    var id: Self { self }
}

struct LibraryItem: Identifiable {
    let id: String
    let title: String
    let media: ContentMode
    var coverURL: URL?
    var readUnits = 0
    var totalUnits = 0
    var downloaded = false
    var bookmarked = false
    var status: LibraryStatus = .ongoing
    var addedAt = Date.distantPast
    var lastRead = Date.distantPast
    var unread: Int { max(0, totalUnits - readUnits) }
    var isCompleted: Bool { totalUnits > 0 && readUnits >= totalUnits }
}

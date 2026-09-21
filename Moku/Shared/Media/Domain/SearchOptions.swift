import Foundation

struct SearchOptions: Equatable, Sendable {
    enum Method: String, CaseIterable, Identifiable, Sendable {
        case keyword = "Keyword"
        case tags = "Tags"
        case source = "Source"
        var id: Self { self }
    }

    enum Sort: String, CaseIterable, Identifiable, Sendable {
        case sourceOrder = "Source order"
        case titleAscending = "Title A–Z"
        case titleDescending = "Title Z–A"
        var id: Self { self }
    }

    enum Status: String, CaseIterable, Identifiable, Sendable {
        case any = "Any"
        case ongoing = "Ongoing"
        case completed = "Completed"
        case hiatus = "Hiatus"
        case cancelled = "Cancelled"
        case finished = "Publishing finished"
        var id: Self { self }
    }

    enum Match: String, CaseIterable, Identifiable, Sendable {
        case all = "Match all"
        case any = "Match any"
        var id: Self { self }
    }

    var method: Method = .keyword
    var media: ContentMode = .all
    var sourceID: String?
    var language: String?
    var genres: Set<String> = []
    var statuses: Set<Status> = []
    var match: Match = .all
    var sort: Sort = .sourceOrder

    var filterCount: Int {
        (method == .keyword ? 0 : 1) + (media == .all ? 0 : 1)
            + (sourceID == nil ? 0 : 1) + (language == nil ? 0 : 1)
            + genres.count + statuses.count
    }
}

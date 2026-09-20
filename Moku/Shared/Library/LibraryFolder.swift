import Foundation

struct LibraryFolder: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var entryIDs: Set<String> = []
    var serverID: String?
    var hidden: Bool?
    var includeInUpdate: Bool?
    var includeInDownload: Bool?
}

struct LibraryOrganization: Codable, Sendable {
    var folders: [LibraryFolder] = []
    var starred: Set<String> = []
    var linkedTitles: [String: Set<String>]?
}

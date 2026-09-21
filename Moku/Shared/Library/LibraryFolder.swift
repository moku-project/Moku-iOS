import Foundation

struct LibraryFolder: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var entryIDs: Set<String> = []
}

struct LibraryOrganization: Codable, Sendable {
    var folders: [LibraryFolder] = []
    var starred: Set<String> = []
}

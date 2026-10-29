import Foundation

struct LibraryFolder: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var entryIDs: Set<String> = []
    var serverID: String?
    var hidden: Bool?
    var includeInUpdate: Bool?
    var includeInDownload: Bool?
    /// Desktop folder content types: empty or nil shows the folder for every type.
    var contentTypes: [ContentMode]?

    func shows(in mode: ContentMode) -> Bool {
        mode == .all || (contentTypes ?? []).isEmpty || contentTypes?.contains(mode) == true
    }
}

struct LibraryOrganization: Codable, Sendable {
    var folders: [LibraryFolder] = []
    var starred: Set<String> = []
    var linkedTitles: [String: Set<String>]?
}

import Foundation

struct MediaEntry: Identifiable, Equatable, Sendable, Codable {
    let id: String
    let title: String
    let media: ContentMode
    let sourceName: String
    let coverURL: URL?
    var extensionID: String? = nil
    var externalID: String? = nil
}

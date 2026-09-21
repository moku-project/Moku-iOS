import Foundation

struct SearchSource: Identifiable, Sendable {
    let id: String
    let name: String
    let language: String
    let media: ContentMode
    let isPinned: Bool
}

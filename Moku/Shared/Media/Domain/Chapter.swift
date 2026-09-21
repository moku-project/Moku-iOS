import Foundation

struct Chapter: Decodable, Sendable, Identifiable {
    let id: String
    let title: String?
    let number: Double?
    let scanlator: String?
    let completed: Bool
    let downloaded: Bool
    var label: String { title ?? number.map { "Chapter \($0.formatted())" } ?? "Chapter" }
}

import Foundation

struct EpisodeStream: Decodable, Sendable {
    struct Source: Decodable, Sendable {
        let label: String
        let url: String
    }
    struct Subtitle: Decodable, Sendable {
        let lang: String
        let url: String
    }
    let url: String
    let sources: [Source]
    let subtitles: [Subtitle]
}

struct SkipMarker: Decodable, Sendable, Equatable {
    let type: String
    let name: String
    let startMs: Int
    let endMs: Int
    var start: Double { Double(startMs) / 1000 }
    var end: Double { Double(endMs) / 1000 }
    /// Desktop button labels: "Skip intro / outro / recap / section".
    var label: String {
        switch type.lowercased() {
        case "op", "intro", "mixed-op": "Skip intro"
        case "ed", "outro", "mixed-ed": "Skip outro"
        case "recap": "Skip recap"
        default: "Skip \(name.isEmpty ? "section" : name.lowercased())"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

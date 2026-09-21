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

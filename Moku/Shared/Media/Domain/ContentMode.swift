import Foundation

enum ContentMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case all, manga, novels, anime

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .all: "Stack"
        case .manga: "ImageSquare"
        case .novels: "BookOpenText"
        case .anime: "FilmSlate"
        }
    }

    /// The server's `ContentType` enum value.
    var graphQLType: String {
        switch self {
        case .anime: "ANIME"
        case .novels: "NOVEL"
        default: "MANGA"
        }
    }
}

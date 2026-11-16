import Foundation

enum ContentMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case all, manga, novels, anime

    var id: Self { self }
    var title: String { rawValue.capitalized }

    /// SF Symbol for covers and rows of this type.
    var symbol: String { systemImage }

    /// The server's `ContentType` enum value.
    var graphQLType: String {
        switch self {
        case .anime: "ANIME"
        case .novels: "NOVEL"
        default: "MANGA"
        }
    }
}

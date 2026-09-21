import Foundation

struct MediaDetails: Decodable, Sendable {
    let id: String
    let title: String
    let thumbnailUrl: String?
    let description: String?
    let author: String?
    let artist: String?
    let status: String?
    let genres: [String]
    var inLibrary: Bool
    var chapters: [Chapter]

    var byline: String {
        [author, artist == author ? nil : artist].compactMap { $0 }.joined(separator: " · ")
    }
}

// Metadata is fetched independently of chapters so a chapter failure cannot hide
// the title, cover, or description. Full responses still decode the chapter list.
extension MediaDetails {
    private enum CodingKeys: String, CodingKey {
        case id, title, thumbnailUrl, description, author, artist, status, genres, inLibrary,
            chapters
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        thumbnailUrl = try values.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        author = try values.decodeIfPresent(String.self, forKey: .author)
        artist = try values.decodeIfPresent(String.self, forKey: .artist)
        status = try values.decodeIfPresent(String.self, forKey: .status)
        genres = try values.decode([String].self, forKey: .genres)
        inLibrary = try values.decode(Bool.self, forKey: .inLibrary)
        chapters = try values.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
    }
}

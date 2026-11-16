import Foundation

/// The title's page on its source site, built from the extension's base URL and the entry's path.
enum SourceLink {
    static func url(mediaID: String) async -> URL? {
        guard Int64(mediaID) != nil else { return nil }
        struct Response: Decodable, Sendable {
            struct Source: Decodable, Sendable { let baseUrl: String? }
            struct Media: Decodable, Sendable {
                let externalId: String
                let source: Source?
            }
            let media: Media?
        }
        guard
            let response: Response = try? await BackendAPI.shared.graphql(
                "{ media(id: \(BackendAPI.literal(mediaID))) { externalId source { baseUrl } } }",
                requiresSourceRuntime: false), let media = response.media
        else { return nil }
        return build(baseURL: media.source?.baseUrl, externalID: media.externalId)
    }

    /// An absolute external ID is used as is; a path is joined to the base URL; anything else has no page.
    nonisolated static func build(baseURL: String?, externalID: String) -> URL? {
        if let absolute = URL(string: externalID), let scheme = absolute.scheme?.lowercased(),
            scheme == "http" || scheme == "https", absolute.host != nil
        {
            return absolute
        }
        guard externalID.hasPrefix("/"), var base = baseURL?.trimmingCharacters(in: .whitespaces),
            base.lowercased().hasPrefix("http")
        else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + externalID)
    }
}

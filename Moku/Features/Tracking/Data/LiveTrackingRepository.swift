import Foundation

struct LiveTrackingRepository: TrackingRepository {
    private var fields: String { "key name configured isLoggedIn authUrl iconUrl username" }
    func services() async throws -> [TrackingService] {
        struct Response: Decodable, Sendable { let trackers: [TrackingService] }
        let response: Response = try await BackendAPI.shared.graphql(
            "{ trackers { \(fields) } }", requiresSourceRuntime: false)
        return response.trackers
    }
    func login(key: String, token: String) async throws {
        struct Response: Decodable, Sendable { let trackerLogin: TrackingService }
        let _: Response = try await BackendAPI.shared.graphql(
            "mutation { trackerLogin(trackerKey: \(BackendAPI.literal(key)), token: \(BackendAPI.literal(token))) { \(fields) } }",
            requiresSourceRuntime: false)
    }
    func logout(key: String) async throws {
        struct Response: Decodable, Sendable { let trackerLogout: Bool }
        let response: Response = try await BackendAPI.shared.graphql(
            "mutation { trackerLogout(trackerKey: \(BackendAPI.literal(key))) }",
            requiresSourceRuntime: false)
        guard response.trackerLogout else {
            throw TrackingError.message("Couldn’t disconnect. Try again.")
        }
    }
    func list(key: String, media: ContentMode, statuses: Set<String>) async throws
        -> [TrackingRemoteEntry]
    {
        struct Response: Decodable, Sendable { let trackerLibrary: [TrackingRemoteEntry] }
        let selected = statuses.sorted().map(BackendAPI.literal).joined(separator: ",")
        let response: Response = try await BackendAPI.shared.graphql(
            "{ trackerLibrary(trackerKey: \(BackendAPI.literal(key)), contentType: \(media == .anime ? "ANIME" : "MANGA"), statuses: [\(selected)]) { remoteId title titleRomaji titleEnglish status progress score coverUrl } }",
            requiresSourceRuntime: false)
        return response.trackerLibrary
    }
    func importTitle(_ item: TrackingImportItem, key: String, media: ContentMode) async throws
        -> MediaEntry
    {
        if let match = item.match {
            let details = try await LiveMediaRepository.shared.metadata(for: match, refresh: false)
            struct Link: Decodable, Sendable { let id: String }
            struct Bound: Decodable, Sendable { let bindTrack: Link }
            let bound: Bound = try await BackendAPI.shared.graphql(
                "mutation { bindTrack(mediaId: \(BackendAPI.literal(details.id)), trackerKey: \(BackendAPI.literal(key)), remoteId: \(BackendAPI.literal(item.id))) { id } }",
                requiresSourceRuntime: false)
            struct Updated: Decodable, Sendable { let updateTrack: Link }
            let _: Updated = try await BackendAPI.shared.graphql(
                "mutation { updateTrack(linkId: \(BackendAPI.literal(bound.bindTrack.id)), status: \(Self.status(item.remote.status)), score: \(item.remote.score), lastChapterRead: \(item.remote.progress)) { id } }",
                requiresSourceRuntime: false)
            return MediaEntry(
                id: details.id, title: match.title, media: media, sourceName: match.sourceName,
                coverURL: match.coverURL, extensionID: match.extensionID,
                externalID: match.externalID)
        }
        struct Created: Decodable, Sendable {
            struct Media: Decodable, Sendable { let id: String }
            let createTrackerStub: Media
        }
        let cover = item.remote.coverUrl.map(BackendAPI.literal) ?? "null"
        let response: Created = try await BackendAPI.shared.graphql(
            "mutation { createTrackerStub(trackerKey: \(BackendAPI.literal(key)), remoteId: \(BackendAPI.literal(item.id)), contentType: \(media == .anime ? "ANIME" : "MANGA"), title: \(BackendAPI.literal(item.remote.title)), coverUrl: \(cover)) { id } }",
            requiresSourceRuntime: false)
        return MediaEntry(
            id: response.createTrackerStub.id, title: item.remote.title, media: media,
            sourceName: "AniList", coverURL: BackendAPI.coverURL(item.remote.coverUrl),
            externalID: "\(key):\(item.id)")
    }
    func linkedIDs(key: String, entries: [MediaEntry]) async throws -> Set<String> {
        struct Media: Decodable, Sendable {
            struct Link: Decodable, Sendable {
                let trackerKey: String
                let remoteId: String
            }
            let trackLinks: [Link]
        }
        var ids = Set<String>()
        for start in stride(from: 0, to: entries.count, by: 40) {
            let batch = entries[start..<min(start + 40, entries.count)]
            let fields = batch.enumerated().map { index, entry in
                "m\(index): media(id: \(BackendAPI.literal(entry.id))) { trackLinks { trackerKey remoteId } }"
            }.joined(separator: " ")
            let response: [String: Media?] = try await BackendAPI.shared.graphql(
                "{ \(fields) }", requiresSourceRuntime: false)
            for media in response.values {
                for link in media?.trackLinks ?? [] where link.trackerKey == key {
                    ids.insert(link.remoteId)
                }
            }
        }
        return ids
    }
    static func status(_ value: String) -> Int {
        switch value {
        case "CURRENT": 1
        case "COMPLETED": 3
        case "PAUSED": 4
        case "DROPPED": 5
        case "PLANNING": 2
        case "REPEATING": 6
        default: 2
        }
    }
}

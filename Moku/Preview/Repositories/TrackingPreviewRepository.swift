#if DEBUG
    import Foundation

    actor TrackingPreviewRepository: TrackingRepository {
        private var connected = true
        func services() async throws -> [TrackingService] {
            [
                TrackingService(
                    key: "anilist", name: "AniList", configured: true, isLoggedIn: connected,
                    authUrl: nil, iconUrl: nil, username: connected ? "moku_reader" : nil),
                TrackingService(
                    key: "mal", name: "MyAnimeList", configured: false, isLoggedIn: false,
                    authUrl: nil, iconUrl: nil, username: nil),
            ]
        }
        func login(key: String, token: String) async throws { connected = true }
        func logout(key: String) async throws { connected = false }
        func list(key: String, media: ContentMode, statuses: Set<String>) async throws
            -> [TrackingRemoteEntry]
        {
            [
                TrackingRemoteEntry(
                    remoteId: "1", title: "Frieren", titleRomaji: nil, titleEnglish: nil,
                    status: "CURRENT", progress: 127, score: 8, coverUrl: nil)
            ]
        }
        func importTitle(_ item: TrackingImportItem, key: String, media: ContentMode) async throws
            -> MediaEntry
        {
            MediaEntry(
                id: item.id, title: item.remote.title, media: media, sourceName: "AniList",
                coverURL: nil,
                externalID: "\(key):\(item.id)")
        }
    }
    struct TrackingPreviewSearch: SearchRepository {
        func sources() async throws -> [SearchSource] { [] }
        func search(_ request: SearchRequest) async throws -> [MediaEntry] { [] }
    }
#endif

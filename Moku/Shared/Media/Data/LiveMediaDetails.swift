import Foundation

extension LiveMediaRepository {
    func details(for entry: MediaEntry, refresh: Bool = false, syncChapters: Bool = true)
        async throws -> MediaDetails
    {
        guard let extensionID = entry.extensionID, let externalID = entry.externalID else {
            throw SearchFailure.notConnected
        }
        struct Response: Decodable, Sendable { let resolveMedia: MediaDetails }
        let result: Response = try await BackendAPI.shared.graphql(
            """
            { resolveMedia(extensionId: \(BackendAPI.literal(extensionID)), externalId: \(BackendAPI.literal(externalID)), syncChapters: \(syncChapters)) {
                id title thumbnailUrl description author artist status genres inLibrary
                \(syncChapters ? "chapters { id title number scanlator completed downloaded uploadedAt sourceOrder }" : "")
            } }
            """, cacheFor: 120, refresh: refresh)
        return result.resolveMedia
    }

    func setSaved(_ saved: Bool, id: String) async throws -> Bool {
        struct Response: Decodable, Sendable {
            struct Media: Decodable, Sendable { let inLibrary: Bool }
            let setInLibrary: Media
        }
        let result: Response = try await BackendAPI.shared.graphql(
            """
            mutation { setInLibrary(mediaId: \(BackendAPI.literal(id)), inLibrary: \(saved)) { inLibrary } }
            """, requiresSourceRuntime: false)
        return result.setInLibrary.inLibrary
    }
}

extension LiveMediaRepository: DetailsRepository {
    func metadata(for entry: MediaEntry, refresh: Bool) async throws -> MediaDetails {
        try await details(for: entry, refresh: refresh, syncChapters: false)
    }

    func chapters(mediaID: String) async throws -> [Chapter] {
        try await chapters(mediaID: mediaID, refresh: false)
    }

    func chapters(mediaID: String, refresh: Bool) async throws -> [Chapter] {
        try Task.checkCancellation()
        if let existing = chapterRequests[mediaID] { return try await existing.value }
        if !refresh, let synced = chaptersSyncedAt[mediaID], Date.now.timeIntervalSince(synced) < 120 {
            // Reopening a title reads current progress from SQLite without asking
            // the extension to rescrape the entire chapter catalog.
            struct Stored: Decodable, Sendable {
                struct Media: Decodable, Sendable { let chapters: [Chapter] }
                let media: Media?
            }
            let stored: Stored = try await BackendAPI.shared.graphql(
                "{ media(id: \(BackendAPI.literal(mediaID))) { chapters { id title number scanlator completed downloaded uploadedAt sourceOrder } } }",
                requiresSourceRuntime: false)
            if let media = stored.media { return media.chapters }
        }
        // Keep the underlying source call alive when a view disappears. A new
        // consumer joins it instead of starting an overlapping extension update.
        let request = Task {
            struct Response: Decodable, Sendable { let syncChapters: [Chapter] }
            let result: Response = try await BackendAPI.shared.graphql(
                """
                mutation { syncChapters(mediaId: \(BackendAPI.literal(mediaID))) {
                    id title number scanlator completed downloaded uploadedAt sourceOrder
                } }
                """)
            return result.syncChapters
        }
        chapterRequests[mediaID] = request
        defer { chapterRequests[mediaID] = nil }
        let chapters = try await request.value
        chaptersSyncedAt[mediaID] = .now
        // Keep this freshness index bounded even across long browsing sessions.
        if chaptersSyncedAt.count > 256 {
            chaptersSyncedAt = chaptersSyncedAt.filter { Date.now.timeIntervalSince($0.value) < 120 }
        }
        return chapters
    }
}

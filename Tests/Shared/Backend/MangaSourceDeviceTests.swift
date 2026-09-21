import Foundation
import XCTest

@testable import Moku

/// Opt-in live regression: uses the app's installed MangaDex source and real
/// embedded JVM/GraphQL/HTTP path. No mock repository or seeded chapter rows.
final class MangaSourceDeviceTests: XCTestCase {
    func testNagatoroAvailabilityMatchesProviderAndCoverLoads() async throws {
        guard ProcessInfo.processInfo.environment["MOKU_LIVE_MANGA_CHECK"] == "1" else {
            throw XCTSkip(
                "Opt-in live source check; requires MangaDex installed on the test device.")
        }
        let source = "eu.kanade.tachiyomi.extension.all.mangadex"
        let id = "d86cf65b-5f6c-437d-a0af-19a31f94ec55"
        let entry = MediaEntry(
            id: "live-nagatoro", title: "Nagatoro", media: .manga,
            sourceName: "MangaDex", coverURL: nil, extensionID: source, externalID: "/manga/\(id)")
        let metadata = try await LiveMediaRepository.shared.metadata(for: entry, refresh: true)
        XCTAssertTrue(metadata.title.localizedCaseInsensitiveContains("Nagatoro"))
        XCTAssertFalse(metadata.description?.isEmpty ?? true)
        let coverURL = try XCTUnwrap(BackendAPI.coverURL(metadata.thumbnailUrl))
        let cover = try await BackendAPI.shared.coverData(for: coverURL)
        _ = try await PageDecoder.shared.decode(cover)
        let chapters = try await LiveMediaRepository.shared.chapters(mediaID: metadata.id)

        // Compare against the provider's English feed excluding external-only
        // publisher links, as the extension does. Availability may change later.
        let url = try XCTUnwrap(
            URL(
                string:
                    "https://api.mangadex.org/manga/\(id)/feed?limit=1&translatedLanguage%5B%5D=en&includeExternalUrl=0"
            ))
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        struct Feed: Decodable { let total: Int }
        let feed = try JSONDecoder().decode(Feed.self, from: data)
        XCTAssertEqual(
            chapters.count, feed.total, "Embedded source differs from the live provider feed")
        let result =
            "MangaDex Nagatoro: provider readable chapters=\(feed.total), embedded chapters=\(chapters.count), decoded cover bytes=\(cover.count)"
        let attachment = XCTAttachment(string: result)
        attachment.lifetime = .keepAlways
        add(attachment)
        print(result)
    }
}

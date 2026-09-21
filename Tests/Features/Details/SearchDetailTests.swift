import Foundation
import Testing

@testable import Moku

@MainActor struct SearchDetailTests {
    private let entry = MediaEntry(
        id: "85", title: "Nagatoro", media: .manga,
        sourceName: "MangaDex", coverURL: nil,
        extensionID: "eu.kanade.tachiyomi.extension.all.mangadex",
        externalID: "/manga/d86cf65b-5f6c-437d-a0af-19a31f94ec55")

    @Test func emptySourceResponseIsNotARequestFailure() async {
        let model = DetailsViewModel(entry: entry, repository: DetailFixture())
        await model.load()
        #expect(model.details?.title == "Fixture title")
        #expect(model.details?.chapters.isEmpty == true)
        #expect(model.error == nil && model.chapterError == nil && !model.loading)
        #expect(model.emptyChapterMessage.contains("MangaDex returned no readable chapters"))
        #expect(
            model.sourceURL?.absoluteString
                == "https://mangadex.org/title/d86cf65b-5f6c-437d-a0af-19a31f94ec55")
    }

    @Test func chapterFailurePreservesMetadataAndCanRetry() async {
        let repository = DetailFixture(fail: true)
        let model = DetailsViewModel(entry: entry, repository: repository)
        await model.load()
        #expect(model.details?.description == "Source description")
        #expect(model.error == nil && model.chapterError != nil && !model.loading)
        await repository.set(fail: false, chapters: ReaderPreview.details.chapters)
        await model.load(refresh: true)
        #expect(model.chapterError == nil)
        #expect(model.details?.chapters.count == 5)
        await repository.set(fail: true)
        await model.load(refresh: true)
        #expect(model.details?.chapters.count == 5)
        #expect(model.chapterError != nil)
    }

    @Test func metadataDecodesWithoutTriggeringChapterResolution() throws {
        let data = Data(#"{"id":"85","title":"Fixture","genres":[],"inLibrary":false}"#.utf8)
        let metadata = try JSONDecoder().decode(MediaDetails.self, from: data)
        #expect(metadata.chapters.isEmpty)
        #expect(metadata.title == "Fixture")
    }

    @Test func sourceLinksRequireKnownSourceAndValidTitleID() {
        var invalid = entry
        invalid.externalID = "/manga/../../other"
        #expect(DetailsViewModel(entry: invalid).sourceURL == nil)
        invalid.externalID = entry.externalID
        invalid.extensionID = "another-source"
        #expect(DetailsViewModel(entry: invalid).sourceURL == nil)
    }
}

private actor DetailFixture: DetailsRepository {
    var fail: Bool
    var list: [Chapter] = []
    init(fail: Bool = false) { self.fail = fail }
    func set(fail: Bool, chapters: [Chapter] = []) {
        self.fail = fail
        list = chapters
    }
    func metadata(for entry: MediaEntry, refresh: Bool) async throws -> MediaDetails {
        MediaDetails(
            id: "85", title: "Fixture title", thumbnailUrl: "/proxy/cover/85",
            description: "Source description", author: nil, artist: nil, status: nil,
            genres: [], inLibrary: false, chapters: [])
    }
    func chapters(mediaID: String) async throws -> [Chapter] {
        if fail { throw URLError(.notConnectedToInternet) }
        return list
    }
}

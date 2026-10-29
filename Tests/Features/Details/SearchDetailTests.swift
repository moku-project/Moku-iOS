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

@MainActor struct HomeTitleLoadingTests {
    private var entry: HomeEntry {
        HomeEntry(MediaEntry(id: "85", title: "Old title", media: .manga,
                             sourceName: "Fixture", coverURL: nil, extensionID: "ext", externalID: "book"))
    }

    @Test func loadsSourceMetadataAndChaptersWithoutAddingActivity() async {
        let fixture = DetailFixture()
        await fixture.set(fail: false, chapters: ReaderPreview.details.chapters)
        let loader = HomeTitleLoader(repository: fixture)
        await loader.load(entry, library: [], refresh: false)
        #expect(loader.updatedEntry?.title == "Fixture title")
        #expect(loader.updatedEntry?.chapters.count == 5)
        #expect(loader.updatedEntry?.sourceEntry == entry.sourceEntry)
        #expect(loader.error == nil && !loader.loading)
    }

    @Test func failedRefreshRetainsChaptersAndCanRetry() async {
        let fixture = DetailFixture(fail: true)
        var original = entry
        original.chapters = [HomeChapter(id: "old", title: "Saved chapter")]
        let loader = HomeTitleLoader(repository: fixture)
        await loader.load(original, library: [], refresh: true)
        #expect(loader.updatedEntry?.chapters.first?.id == "old")
        #expect(loader.updatedEntry?.summary == "Source description")
        #expect(loader.error != nil)
        await fixture.set(fail: false, chapters: ReaderPreview.details.chapters)
        await loader.load(original, library: [], refresh: true)
        #expect(loader.error == nil && loader.updatedEntry?.chapters.count == 5)
    }

    @Test func scanlatorPreferencesSelectPreferredReleasesAndExcludeBlockedGroups() {
        let chapters = [
            Chapter(id: "a", title: "One", number: 1, scanlator: "A", completed: false, downloaded: false),
            Chapter(id: "b", title: "One", number: 1, scanlator: "B", completed: false, downloaded: false),
            Chapter(id: "c", title: "Two", number: 2, scanlator: "A", completed: false, downloaded: false),
            Chapter(id: "d", title: "Extra", number: nil, scanlator: "B", completed: false, downloaded: false)
        ]
        var prefs = ChapterDisplayPreferences(included: ["B"])
        #expect(Set(prefs.apply(chapters).map(\.id)) == ["b", "c", "d"])
        prefs.onlyIncluded = true
        #expect(Set(prefs.apply(chapters).map(\.id)) == ["b", "d"])
        prefs.excluded = ["B"]
        #expect(prefs.apply(chapters).isEmpty)
    }
}

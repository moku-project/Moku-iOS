import Foundation
import Testing
import UIKit

@testable import Moku

@MainActor struct ReaderTests {
    @Test func settingsPersistWithOverridesAndPresets() throws {
        let suite = "reader-test.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReaderPreferences(defaults: defaults)
        #expect(preferences.document.global.pageStyle == "longstrip")
        #expect(preferences.document.behaviour.preloadPages == 3)
        preferences.toggleOverride("one")
        var settings = preferences.settings(for: "one")
        settings.pageStyle = "double"
        settings.readingDirection = "rtl"
        preferences.set(settings, for: "one")
        preferences.savePreset("  Manga  ", mediaID: "one")
        preferences.document.bookmarks["one"] = ReaderPosition(chapterID: "2", page: 6)
        let restored = ReaderPreferences(defaults: defaults)
        #expect(restored.settings(for: "one").pageStyle == "double")
        #expect(restored.settings(for: "two").pageStyle == "longstrip")
        #expect(restored.document.presets.first?.name == "Manga")
        #expect(restored.document.bookmarks["one"]?.page == 6)
        restored.toggleOverride("one")
        #expect(restored.settings(for: "one") == restored.document.global)
    }
    @Test func oddSpreadsAndOffsetNeverLosePages() {
        #expect(
            ReaderPagination.groups(count: 5, double: true, offset: false) == [
                [1], [2, 3], [4, 5],
            ])
        #expect(
            ReaderPagination.groups(count: 5, double: true, offset: true) == [
                [1], [2], [3, 4], [5],
            ])
        #expect(ReaderPagination.groups(count: 0, double: true, offset: true).isEmpty)
        let groups = ReaderPagination.groups(count: 5, double: true, offset: true)
        #expect(ReaderPagination.adjacent(page: 3, groups: groups, forward: true) == 5)
        #expect(ReaderPagination.adjacent(page: 1, groups: groups, forward: false) == nil)
    }
    @Test func navigationPersistsProgressAndDownloadUsesCurrentChapter() async throws {
        let suite = "reader-test.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReaderPreferences(defaults: defaults)
        preferences.document.global.pageStyle = "single"
        let repository = RecordingReaderRepository()
        let model = ReaderViewModel(
            details: ReaderPreview.details, chapterID: "11", preferences: preferences,
            repository: repository)
        await model.load()
        model.jump(100)
        #expect(model.page == 5)
        model.toggleBookmark()
        #expect(model.bookmarked)
        await model.flush()
        let progress = await repository.updates
        #expect(progress.last?.completed == true)
        #expect(preferences.document.positions[model.details.id]?.page == 5)
        await model.download([model.chapterID])
        #expect(await repository.downloads == ["11"])
        let resumed = ReaderViewModel(
            details: ReaderPreview.details, chapterID: "11",
            preferences: ReaderPreferences(defaults: defaults), repository: repository)
        await resumed.load()
        #expect(resumed.page == 5)
        model.changeChapter(forward: true)
        await model.load()
        #expect(model.chapterID == "12")
        #expect(model.page == 1)
    }
    @Test func failureDoesNotLeaveReaderLoading() async throws {
        let preferences = ReaderPreferences(defaults: .standard)
        let model = ReaderViewModel(
            details: ReaderPreview.details, chapterID: "11", preferences: preferences,
            repository: FailingReaderRepository())
        await model.load()
        #expect(!model.loading && model.error != nil && model.pages.isEmpty)
    }
    @Test func corruptPageIsRejected() async {
        await #expect(throws: (any Error).self) {
            try await PageDecoder.shared.decode(Data("not an image".utf8))
        }
    }
    @Test func everyDeclaredPhosphorAssetIsBundled() throws {
        struct Manifest: Decodable {
            let icons: [String]
            let weights: [String]
        }
        let url = try #require(
            Bundle.main.url(forResource: "phosphor-manifest", withExtension: "json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        for icon in manifest.icons {
            for weight in manifest.weights {
                #expect(UIImage(named: icon + "-" + weight) != nil, "Missing \(icon)-\(weight)")
            }
        }
    }
    @Test func imageDecodeBoundsPixelsAndPreservesOriginalGeometry() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 4096, height: 128), format: format)
            .pngData { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 4096, height: 128))
            }
        let image = try await PageDecoder.shared.decode(data)
        #expect((image.cgImage?.width ?? 9999) <= 2048)
        #expect(abs(image.size.width - 4096) < 1)
    }
    @Test func desktopReaderIconsAreBundled() throws {
        for name in [
            "Sliders-regular", "ArrowLeft-light", "ArrowRight-light", "Bookmark-fill", "Rows-light",
            "ArrowsLeftRight-fill",
        ] {
            #expect(UIImage(named: name) != nil, "Missing \(name)")
        }
    }
}

actor RecordingReaderRepository: ReaderRepository {
    struct Update: Sendable {
        let chapter: String
        let value: Double
        let completed: Bool
    }
    var updates: [Update] = []
    var downloads: [String] = []
    func pages(chapterID: String) async throws -> [String] { (1...5).map { "page/\($0)" } }
    func image(path: String) async throws -> Data { Data() }
    func progress(mediaID: String, chapterID: String, value: Double, completed: Bool) async throws {
        updates.append(Update(chapter: chapterID, value: value, completed: completed))
    }
    func download(mediaID: String, chapterIDs: [String]) async throws { downloads = chapterIDs }
}
struct FailingReaderRepository: ReaderRepository {
    func pages(chapterID: String) async throws -> [String] {
        throw URLError(.notConnectedToInternet)
    }
    func image(path: String) async throws -> Data { throw URLError(.notConnectedToInternet) }
    func progress(mediaID: String, chapterID: String, value: Double, completed: Bool) async throws {
    }
    func download(mediaID: String, chapterIDs: [String]) async throws {}
}

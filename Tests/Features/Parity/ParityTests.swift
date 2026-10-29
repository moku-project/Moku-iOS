import Foundation
import Testing

@testable import Moku

/// Pure logic behind the desktop-parity features.
@MainActor struct ParityTests {
    @Test func novelHTMLBecomesTypesetBlocks() throws {
        let html = """
            <html><head><style>p { color: red }</style></head><body>
            <h2>Chapter 1</h2>
            <p>It was a <em>quiet</em> night &amp; the <strong>moon</strong> rose.</p>
            <p>   </p><hr/><p>Second&nbsp;line&hellip;<br>Third line</p>
            <script>alert(1)</script></body></html>
            """
        let document = NovelDocument.parse(html, isHTML: true)
        #expect(document.blocks.count == 5)
        guard case .heading(let heading) = document.blocks[0] else { Issue.record("no heading"); return }
        #expect(String(heading.characters) == "Chapter 1")
        guard case .paragraph(let first) = document.blocks[1] else { Issue.record("no paragraph"); return }
        #expect(String(first.characters) == "It was a quiet night & the moon rose.")
        #expect(first.runs.contains { $0.inlinePresentationIntent == .emphasized })
        #expect(document.blocks[2] == .rule)
        guard case .paragraph(let second) = document.blocks[3] else { Issue.record("no second"); return }
        #expect(String(second.characters) == "Second\u{00A0}line…")
        #expect(!document.blocks.contains { block in
            if case .paragraph(let text) = block { return String(text.characters).contains("alert") }
            return false
        })
    }

    @Test func plainNovelTextSplitsParagraphs() {
        let document = NovelDocument.parse("One.\r\n\r\nTwo three.\n", isHTML: false)
        #expect(document.blocks.count == 2)
        #expect(document.wordCount == 3)
    }

    @Test func genreFiltersMapOntoSourceFilterTrees() {
        let tree = [
            FilterBuilder.Node(typename: "GroupFilter", name: "Genres", values: nil, children: [
                .init(typename: "TriStateFilter", name: "Comedy", values: nil, children: nil),
                .init(typename: "TriStateFilter", name: "Drama", values: nil, children: nil),
            ]),
            .init(typename: "SelectFilter", name: "Status", values: ["Any", "Ongoing", "Completed"], children: nil),
        ]
        let built = FilterBuilder.inputs(tree, genres: ["comedy"], statuses: ["Completed"])
        #expect(built.matchedAll)
        #expect(built.literal.contains("tristate: {state: 1}"))
        #expect(built.literal.contains("select: {state: 2}"))
        #expect(!built.literal.contains("Drama"))
        // A genre the source doesn't know must not silently become an unfiltered search.
        #expect(!FilterBuilder.inputs(tree, genres: ["Mecha"], statuses: []).matchedAll)
    }

    @Test func desktopAddressesNormaliseToTheServerPort() {
        #expect(DesktopClient.normalize("192.168.1.20")?.absoluteString == "http://192.168.1.20:6007")
        #expect(DesktopClient.normalize(" mac.local:6107 ")?.absoluteString == "http://mac.local:6107")
        #expect(DesktopClient.normalize("https://moku.example/path?x=1")?.absoluteString == "https://moku.example:6007")
        #expect(DesktopClient.normalize("") == nil)
        #expect(DesktopClient.normalize("ftp://host") == nil)
    }

    @Test func skipMarkersUseDesktopLabels() {
        #expect(SkipMarker(type: "op", name: "", startMs: 0, endMs: 1).label == "Skip intro")
        #expect(SkipMarker(type: "ED", name: "", startMs: 0, endMs: 1).label == "Skip outro")
        #expect(SkipMarker(type: "recap", name: "", startMs: 0, endMs: 1).label == "Skip recap")
        #expect(SkipMarker(type: "x", name: "", startMs: 0, endMs: 1).label == "Skip section")
    }

    @Test func librarySourceStatusesMapToFilters() {
        #expect(LibraryStatus(source: "ONGOING") == .ongoing)
        #expect(LibraryStatus(source: "on_hiatus") == .hiatus)
        #expect(LibraryStatus(source: "Publishing finished") == .finished)
        #expect(LibraryStatus(source: "COMPLETED") == .completed)
        #expect(LibraryStatus(source: "unknown") == nil)
        #expect(LibraryStatus(source: nil) == nil)
    }

    @Test func migrationRanksCloseTitlesFirst() {
        #expect(MigrateSheet.score("Rent-A-Girlfriend", "Rent A Girlfriend") == 1)
        #expect(MigrateSheet.score("Rent-A-Girlfriend", "Rent A Girlfriend Mythology") < 1)
        #expect(MigrateSheet.score("abc", "") == 0)
    }

    @Test func chapterSortModesAndReadingOrder() async {
        let chapters = [
            Chapter(id: "a", title: nil, number: 2, scanlator: nil, completed: false, downloaded: false, uploadedAt: "2024-01-03T00:00:00Z", sourceOrder: 0),
            Chapter(id: "b", title: nil, number: 1, scanlator: nil, completed: true, downloaded: false, uploadedAt: "2024-01-01T00:00:00Z", sourceOrder: 1),
            Chapter(id: "c", title: nil, number: 3, scanlator: nil, completed: false, downloaded: false, uploadedAt: "2024-01-02T00:00:00Z", sourceOrder: 2),
        ]
        let byUpload = await ChapterPresentation.filtered(chapters, preferences: Data(), mediaID: "m", query: "", ascending: false, sort: .uploaded)
        #expect(byUpload.map(\.id) == ["a", "c", "b"])
        let byNumber = await ChapterPresentation.filtered(chapters, preferences: Data(), mediaID: "m", query: "", ascending: true, sort: .number)
        #expect(byNumber.map(\.id) == ["b", "a", "c"])
        #expect(ChapterPresentation.readingOrder(chapters, preferences: Data(), mediaID: "m").map(\.id) == ["b", "a", "c"])
    }
}

@MainActor struct ThemeInteropTests {
    @Test func themesRoundTripThroughDesktopJSON() throws {
        let theme = NativeTheme(name: "Dusk", background: "#101820", surface: "#18222c", accent: "#88aacc", text: "#f0f0f0")
        let imported = try #require(NativeTheme(desktopJSON: theme.desktopJSON))
        #expect(imported.name == "Dusk")
        #expect(imported.background == "#101820" && imported.surface == "#18222c" && imported.accent == "#88aacc")
        #expect(!imported.isLight)
        let desktop = ##"{"id":"custom:1","name":"Paper","tokens":{"bg-base":"#f4f2ee","text-primary":"#1a1916","accent":"#2a5a2a"}}"##
        let paper = try #require(NativeTheme(desktopJSON: desktop))
        #expect(paper.isLight && paper.accent == "#2a5a2a")
        #expect(NativeTheme(desktopJSON: "not json") == nil)
    }
}

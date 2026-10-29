import Foundation
import Testing

@testable import Moku

/// Desktop features ported in the final parity pass.
struct RemainingParityTests {
    @Test func parsesASSStylesOverridesAndPositions() {
        let cues = SubtitleCue.parse(
            """
            [Script Info]
            ScriptType: v4.00+

            [V4+ Styles]
            Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
            Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1
            Style: Sign,Arial,40,&H0000FFFF,&H000000FF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,2,2,8,10,10,10,1

            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            Dialogue: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,Hello, world\\Nsecond line
            Dialogue: 0,0:00:02.00,0:00:04.00,Sign,,0,0,0,,{\\an8}Station
            Dialogue: 0,0:00:05.00,0:00:06.00,Default,,0,0,0,,{\\i1\\c&H0000FF&}Red italic
            Dialogue: 0,0:00:07.00,0:00:08.00,Default,,0,0,0,,{\\p1}m 0 0 l 10 10{\\p0}
            """)
        #expect(cues.count == 3)
        #expect(cues[0].text == "Hello, world\nsecond line")
        #expect(cues[0].start == 1 && cues[0].end == 3.5)
        #expect(cues[0].position == .bottom && cues[0].color == nil && !cues[0].bold)
        #expect(cues[1].position == .top && cues[1].bold)
        #expect(cues[1].color == 0xFFFF00)
        #expect(cues[2].italic && cues[2].color == 0xFF0000)
    }

    @Test func folderContentTypesLimitWhereFoldersShow() {
        var folder = LibraryFolder(name: "Seasonal")
        #expect(folder.shows(in: .anime) && folder.shows(in: .manga))
        folder.contentTypes = [.anime]
        #expect(folder.shows(in: .anime))
        #expect(!folder.shows(in: .manga))
        #expect(folder.shows(in: .all))
    }

    @MainActor @Test func coverPickerRecoversOriginalURLsFromProxiedCovers() {
        let original = "https://uploads.example.org/covers/ab.jpg?width=512"
        let proxied = BackendAPI.coverURL(original)!
        #expect(CoverPickerSheet.original(proxied) == original)
        #expect(CoverPickerSheet.original(URL(string: "/proxy/cover/12")!) == nil)
    }

    @MainActor @Test func storageEstimateScalesWithMedia() {
        #expect(StorageGuard.estimate(count: 2, media: .manga) == 60_000_000)
        #expect(StorageGuard.estimate(count: 1, media: .anime) > StorageGuard.estimate(count: 1, media: .manga))
    }

    @Test func novelBookmarksRoundTrip() {
        let marks = ["42": NovelBookmark(chapterID: "7", fraction: 0.4)]
        #expect(NovelBookmark.all(NovelBookmark.encode(marks)) == marks)
        #expect(NovelBookmark.all(Data()).isEmpty)
    }
}

import Foundation
import Testing
import UIKit

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
        // The \p1 drawing is now a shape cue rather than skipped.
        #expect(cues.count == 4)
        #expect(cues[3].text.isEmpty && cues[3].shape.count == 2)
        #expect(cues[0].text == "Hello, world\nsecond line")
        #expect(cues[0].start == 1 && cues[0].end == 3.5)
        #expect(cues[0].position == .bottom && cues[0].color == nil && !cues[0].bold)
        #expect(cues[1].position == .top && cues[1].bold)
        #expect(cues[1].color == 0xFFFF00)
        #expect(cues[2].italic && cues[2].color == 0xFF0000)
    }

    @Test func parsesASSFontsSizesOutlinesAndPositions() {
        let cues = SubtitleCue.parse(
            """
            [Script Info]
            PlayResX: 1920
            PlayResY: 1080

            [V4+ Styles]
            Format: Name, Fontname, Fontsize, PrimaryColour, OutlineColour, Bold, Italic, Outline, Alignment
            Style: Default,Avenir Next,54,&H00FFFFFF,&H00000000,0,0,3,2
            Style: Note,Georgia,40,&H00FFFFFF,&H00FF0000,0,0,0,4

            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Line
            Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\\an9\\pos(1800,108)\\fs108\\3c&H0000FF&\\bord6}Sign
            Dialogue: 0,0:00:01.00,0:00:02.00,Note,,0,0,0,,Aside
            """)
        #expect(cues.count == 3)
        let line = cues[0], sign = cues[1], aside = cues[2]
        #expect(line.fontName == "Avenir Next" && line.size == 0.05 && line.horizontal == .center)
        #expect(line.outline == 0x000000 && line.outlineWidth == 3.0 / 1080 && line.anchor == nil)
        #expect(sign.position == .top && sign.horizontal == .right)
        #expect(sign.anchor == CGPoint(x: 1800.0 / 1920, y: 0.1))
        #expect(sign.size == 0.1 && sign.outline == 0xFF0000 && sign.outlineWidth == 6.0 / 1080)
        // No border width means no outline, whatever the colour.
        #expect(aside.horizontal == .left && aside.position == .middle && aside.outline == nil)
    }

    @Test func animatesASSFadesAndMoves() {
        let cues = SubtitleCue.parse(
            """
            [Script Info]
            PlayResX: 1000
            PlayResY: 1000

            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            Dialogue: 0,0:00:10.00,0:00:14.00,Default,,0,0,0,,{\\fad(1000,500)}Fades
            Dialogue: 0,0:00:10.00,0:00:14.00,Default,,0,0,0,,{\\move(0,0,1000,500,1000,3000)}Moves
            """)
        let fade = cues[0], move = cues[1]
        #expect(fade.isAnimated && move.isAnimated)
        #expect(fade.opacity(at: 10) == 0)
        #expect(fade.opacity(at: 10.5) == 0.5)
        #expect(fade.opacity(at: 12) == 1)
        #expect(fade.opacity(at: 13.75) == 0.5)
        #expect(move.anchor(at: 10.5) == CGPoint(x: 0, y: 0))
        #expect(move.anchor(at: 12) == CGPoint(x: 0.5, y: 0.25))
        #expect(move.anchor(at: 13.5) == CGPoint(x: 1, y: 0.5))
    }

    @Test func parsesASSKaraokeTransformsAndAlpha() {
        let cues = SubtitleCue.parse(
            """
            [Script Info]
            PlayResY: 1000

            [V4+ Styles]
            Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, Bold, Italic, Outline, Alignment
            Style: Song,Arial,50,&H00FFFFFF,&H000000FF,&H00000000,0,0,2,8

            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            Dialogue: 0,0:00:10.00,0:00:14.00,Song,,0,0,0,,{\\k50}Ka{\\k100}ra{\\kf150}o{\\k0}ke
            Dialogue: 0,0:00:10.00,0:00:14.00,Song,,0,0,0,,{\\fs50\\t(1000,3000,\\fs100\\c&H0000FF&\\alpha&HFF&)}Grow
            Dialogue: 0,0:00:10.00,0:00:14.00,Song,,0,0,0,,{\\alpha&H80&}Half
            """)
        #expect(cues.count == 3)
        let song = cues[0], grow = cues[1], half = cues[2]
        #expect(song.text == "Karaoke")
        #expect(song.karaoke.map(\.text) == ["Ka", "ra", "o", "ke"])
        #expect(song.karaoke.map(\.start) == [0, 0.5, 1.5, 3.0])
        #expect(song.secondary == 0xFF0000)
        #expect(!song.sung(1, at: 10.4) && song.sung(1, at: 10.5) && song.sung(3, at: 13.5))
        // Transform targets don't leak into the static style.
        #expect(grow.size == 0.05 && grow.color == nil && grow.alpha == 1)
        #expect(grow.size(at: 10.5) == 0.05)
        #expect(abs((grow.size(at: 12) ?? 0) - 0.075) < 0.000_001)
        #expect(grow.size(at: 13.5) == 0.1)
        #expect(grow.color(at: 13.5) == 0xFF0000)
        #expect(grow.alpha(at: 12) == 0.5)
        #expect(abs(half.alpha - (1 - 128.0 / 255)) < 0.001)
        #expect(song.isAnimated && grow.isAnimated && !half.isAnimated)
    }

    @Test func parsesASSRotationScalingClipsAndShapes() {
        let cues = SubtitleCue.parse(
            """
            [Script Info]
            PlayResX: 1000
            PlayResY: 500

            [V4+ Styles]
            Format: Name, Fontname, Fontsize, PrimaryColour, ScaleX, ScaleY, Angle, Alignment
            Style: Sign,Arial,40,&H00FFFFFF,150,80,10,7

            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            Dialogue: 0,0:00:01.00,0:00:02.00,Sign,,0,0,0,,{\\pos(100,50)\\frz-15\\fscx200\\clip(0,0,500,250)}Turned
            Dialogue: 0,0:00:01.00,0:00:02.00,Sign,,0,0,0,,{\\pos(100,50)\\iclip(10,20,30,40)\\p1}m 0 0 l 100 0 100 50 0 50 c
            Dialogue: 0,0:00:01.00,0:00:02.00,Sign,,0,0,0,,{\\p2}m 0 0 b 40 0 80 40 80 80{\\p0}
            Dialogue: 0,0:00:01.00,0:00:02.00,Sign,,0,0,0,,{\\p1}nothing here
            """)
        #expect(cues.count == 3)
        let text = cues[0], box = cues[1], curve = cues[2]
        #expect(text.text == "Turned" && text.shape.isEmpty)
        #expect(text.rotation == -15 && text.scaleX == 2 && text.scaleY == 0.8)
        #expect(text.clip == CGRect(x: 0, y: 0, width: 0.5, height: 0.5) && !text.clipInverted)
        #expect(box.text.isEmpty && box.clipInverted)
        #expect(box.clip == CGRect(x: 0.01, y: 0.04, width: 0.02, height: 0.04))
        #expect(box.rotation == 10)
        #expect(box.shape == [
            .move(CGPoint(x: 0, y: 0)), .line(CGPoint(x: 0.1, y: 0)), .line(CGPoint(x: 0.1, y: 0.1)),
            .line(CGPoint(x: 0, y: 0.1)), .close,
        ])
        // \\p2 halves the coordinates.
        #expect(curve.shape == [
            .move(CGPoint(x: 0, y: 0)),
            .curve(CGPoint(x: 0.02, y: 0), CGPoint(x: 0.04, y: 0.04), CGPoint(x: 0.04, y: 0.08)),
        ])
    }

    @Test func parsesASSShadowBlurTiltAndDrawingClips() {
        let cues = SubtitleCue.parse(
            """
            [Script Info]
            PlayResX: 1000
            PlayResY: 500

            [V4+ Styles]
            Format: Name, Fontname, Fontsize, PrimaryColour, BackColour, Shadow, Alignment
            Style: Default,Arial,40,&H00FFFFFF,&H00FF0000,2,2

            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Plain
            Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\\shad5\\4c&H0000FF&\\blur2\\frx20\\fry-10\\pos(10,10)\\iclip(m 0 0 l 500 0 500 250)}Tilted
            Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\\be1\\clip(2,m 0 0 l 200 0 200 200)}Soft
            """)
        #expect(cues.count == 3)
        let plain = cues[0], tilted = cues[1], soft = cues[2]
        #expect(plain.shadowDepth == 2.0 / 500 && plain.shadowColor == 0x0000FF && plain.blur == 0)
        #expect(tilted.shadowDepth == 5.0 / 500 && tilted.shadowColor == 0xFF0000)
        #expect(tilted.blur == 2.0 / 500 && tilted.rotationX == 20 && tilted.rotationY == -10)
        #expect(tilted.clipInverted && tilted.clip == nil)
        #expect(tilted.clipShape == [.move(CGPoint(x: 0, y: 0)), .line(CGPoint(x: 0.5, y: 0)), .line(CGPoint(x: 0.5, y: 0.5))])
        // \clip(2, …) halves the drawing's coordinates; \be counts as blur.
        #expect(soft.blur == 1.0 / 500 && !soft.clipInverted)
        #expect(soft.clipShape == [.move(CGPoint(x: 0, y: 0)), .line(CGPoint(x: 0.1, y: 0)), .line(CGPoint(x: 0.1, y: 0.2))])
    }

    @Test func decodesFontsEmbeddedInASS() {
        let bytes = Data((0..<200).map { UInt8($0 % 251) })
        let encoded = Self.ssaEncode(bytes)
        #expect(SubtitleFonts.decode(encoded) == bytes)
        // Lines are wrapped at 80 characters in real files.
        var wrapped = ""
        var rest = Substring(encoded)
        while !rest.isEmpty { wrapped += rest.prefix(80) + "\n"; rest = rest.dropFirst(80) }
        let script = "[Script Info]\nTitle: x\n\n[Fonts]\nfontname: Example.ttf\n\(wrapped)\n[Events]\n"
        let fonts = SubtitleFonts.embedded(in: script)
        #expect(fonts.count == 1)
        #expect(fonts.first?.name == "Example.ttf")
        #expect(fonts.first?.data == bytes)
        #expect(SubtitleFonts.decode("~~~ not uu") == nil)
    }

    private static func ssaEncode(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var out = ""
        func char(_ value: Int) -> Character { Character(UnicodeScalar(UInt8(value + 33))) }
        var index = 0
        while index < bytes.count {
            let chunk = Array(bytes[index..<min(index + 3, bytes.count)])
            let a = Int(chunk[0]), b = chunk.count > 1 ? Int(chunk[1]) : 0, c = chunk.count > 2 ? Int(chunk[2]) : 0
            let values = [a >> 2, (a & 3) << 4 | b >> 4, (b & 0xF) << 2 | c >> 6, c & 0x3F]
            out += String(values.prefix(chunk.count + 1).map(char))
            index += 3
        }
        return out
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

    @Test func recognisesPDFPagePaths() {
        let parsed = PDFPageSource.parse("/content/12/34/pdfpage/3")
        #expect(parsed?.document == "/content/12/34/pdf")
        #expect(parsed?.index == 2)
        #expect(PDFPageSource.parse("/content/12/34/pages/3") == nil)
        #expect(PDFPageSource.parse("/content/12/34/pdfpage/0") == nil)
    }

    @Test func rendersPDFPagesOnceDownloaded() async throws {
        // Two pages: portrait, then landscape.
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).pdfData { context in
            context.beginPage()
            context.beginPage(withBounds: CGRect(x: 0, y: 0, width: 800, height: 400), pageInfo: [:])
        }
        let downloads = Counter()
        let source = PDFPageSource()
        let load: @Sendable (String) async throws -> Data = { path in
            #expect(path == "/content/7/9/pdf")
            await downloads.increment()
            return pdf
        }
        let first = try await source.image(path: "/content/7/9/pdfpage/1", load: load)
        let second = try await source.image(path: "/content/7/9/pdfpage/2", load: load)
        #expect(await downloads.value == 1)
        let portrait = try #require(UIImage(data: first)).size
        let landscape = try #require(UIImage(data: second)).size
        #expect(portrait.height > portrait.width)
        #expect(landscape.width > landscape.height)
        await #expect(throws: (any Error).self) { try await source.image(path: "/content/7/9/pdfpage/3", load: load) }
    }

    @Test func mapsDesktopFolderContentTypes() {
        #expect(["MANGA", "NOVEL", "ANIME", "OTHER"].compactMap(DesktopSync.contentMode) == [.manga, .novels, .anime])
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

import Foundation
import Testing

@testable import Moku

struct PlayerTests {
    @MainActor @Test func firstLoadWaitsBeforeStartingPlayback() async {
        let model = PlayerViewModel.preview()
        let started = ContinuousClock.now
        await model.load(minimumLoadingDuration: .milliseconds(80))
        #expect(started.duration(to: .now) >= .milliseconds(80))
        #expect(!model.loading)
        model.stop()
    }

    @MainActor @Test func cancelledMinimumCycleNeverStartsPlayback() async throws {
        let model = PlayerViewModel.preview()
        let load = Task { await model.load(minimumLoadingDuration: .seconds(10)) }
        try await Task.sleep(for: .milliseconds(20))
        load.cancel()
        await load.value
        #expect(model.player.currentItem == nil)
        #expect(!model.playing)
        model.stop()
    }

    @Test func parsesWebVTTSettingsAndMultilineCues() {
        let cues = SubtitleCue.parse(
            """
            WEBVTT

            intro
            00:01.000 --> 00:03.500 align:center
            <i>Hello</i> &amp; welcome
            Second line

            00:04.000 --> 00:05.000
            Next cue
            """)
        #expect(cues.count == 2)
        #expect(cues[0] == SubtitleCue(start: 1, end: 3.5, text: "Hello & welcome\nSecond line"))
    }
    @Test func parsesSRTAndRejectsInvalidIntervals() {
        let cues = SubtitleCue.parse(
            "1\r\n00:01:02,500 --> 00:01:05,000\r\nHello\r\n\r\n2\r\n00:08.000 --> 00:07.000\r\nInvalid"
        )
        #expect(cues == [SubtitleCue(start: 62.5, end: 65, text: "Hello")])
        #expect(SubtitleCue.parse("[Script Info]\nFormat: ASS").isEmpty)
        #expect(SubtitleCue.parse("00:01.000 --> ").isEmpty)
        #expect(SubtitleCue.timestamp("bad:01:02") == nil)
    }
    @MainActor @Test func formatsUnknownAndHourDurations() {
        #expect(PlayerViewModel.time(.nan) == "0:00")
        #expect(PlayerViewModel.time(-4) == "0:00")
        #expect(PlayerViewModel.time(.infinity) == "0:00")
        #expect(!PlayerViewModel.time(.greatestFiniteMagnitude).isEmpty)
        #expect(PlayerViewModel.time(3692) == "1:01:32")
    }
    @MainActor @Test func seeksAreBoundedAndCaptionEndIsExclusive() {
        let model = PlayerViewModel.preview()
        model.duration = 24
        model.seek(-10)
        #expect(model.position == 0)
        model.seek(90)
        #expect(model.position == 24)
        model.seek(.nan)
        #expect(model.position == 24)
        model.duration = .infinity
        model.seek(5)
        #expect(model.position == 24)
        model.cues = [.init(start: 1, end: 3, text: "One"), .init(start: 3, end: 5, text: "Two")]
        model.position = 3
        #expect(model.caption == "Two")
    }
    @MainActor @Test func switchingSourcesPreservesPausedPlayback() async {
        let model = PlayerViewModel.preview()
        await model.load()
        model.stream = EpisodeStream(
            url: "preview",
            sources: [
                .init(label: "Alternative", url: "preview")
            ], subtitles: [])
        // Autoplay controls initial loads, not a viewer's explicit pause.
        model.autoplay = true
        model.position = 12
        await model.changeSource(0)
        #expect(model.sourceIndex == 0)
        #expect(!model.playing)
        #expect(model.player.rate == 0)
        model.stop()
    }

    @MainActor @Test func stoppingDuringExtractionDiscardsTheLateResult() async {
        let repository = DelayedPlayerRepository()
        let model = PlayerViewModel(
            title: "Fixture", mediaID: "1", chapters: [],
            chapterID: "1", repository: repository)
        let load = Task { await model.load() }
        // The gate signals entry without timing assumptions or a live source.
        await repository.waitForExtraction()
        model.stop()
        await repository.finishExtraction()
        await load.value
        #expect(model.player.currentItem == nil)
        #expect(!model.playing)
        #expect(!model.loading)
        #expect(model.stream == nil)
    }

}

private actor DelayedPlayerRepository: PlayerRepository {
    private var extraction: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    func waitForExtraction() async {
        if extraction != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func finishExtraction() {
        extraction?.resume()
        extraction = nil
    }
    func stream(chapterID: String) async throws -> (EpisodeStream, Double) {
        await withCheckedContinuation {
            extraction = $0
            entered?.resume()
            entered = nil
        }
        return (EpisodeStream(url: "preview", sources: [], subtitles: []), 0)
    }
    func request(path: String) async throws -> URLRequest {
        try await PlayerPreviewRepository().request(path: path)
    }
    func subtitle(path: String) async throws -> String { "" }
    func save(mediaID: String, chapterID: String, position: Double, duration: Double) async throws {
    }
}

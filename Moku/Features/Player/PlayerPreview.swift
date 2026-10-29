#if DEBUG
    import Foundation
    import SwiftUI

    /// Deterministic local media for simulator review and UI tests. Never used by episode launches.
    struct PlayerPreviewRepository: PlayerRepository {
        func stream(chapterID: String) async throws -> (EpisodeStream, Double) {
            (
                EpisodeStream(
                    url: "preview", sources: [],
                    subtitles: [
                        .init(lang: "English", url: "english"),
                        .init(lang: "Español", url: "spanish"),
                        .init(lang: "Signs (ASS)", url: "signs"),
                    ]), 8
            )
        }
        func request(path: String) async throws -> URLRequest {
            let url = Bundle.main.url(forResource: "player-preview", withExtension: "mp4")!
            return URLRequest(url: url)
        }
        func subtitle(path: String) async throws -> String {
            if path == "signs" {
                return """
                    [Script Info]
                    ScriptType: v4.00+
                    PlayResX: 1920
                    PlayResY: 1080

                    [V4+ Styles]
                    Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, Bold, Italic, Outline, Alignment
                    Style: Default,Avenir Next,64,&H00FFFFFF,&H00FFFFFF,&H00000000,0,0,3,2
                    Style: Sign,Georgia,52,&H0000FFFF,&H0000FFFF,&H00402010,-1,0,2,7
                    Style: Song,Avenir Next,56,&H0080C0FF,&H00FFFFFF,&H00301000,-1,0,2,9

                    [Events]
                    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
                    Dialogue: 0,0:00:00.00,0:00:24.00,Sign,,0,0,0,,{\\pos(100,120)\\c&H302010&\\bord0\\p1}m 0 0 l 760 0 760 110 0 110{\\p0}
                    Dialogue: 0,0:00:00.00,0:00:24.00,Sign,,0,0,0,,{\\pos(120,140)\\frz4}Northbound platform
                    Dialogue: 0,0:00:00.00,0:00:24.00,Default,,0,0,0,,{\\i1\\shad3\\4c&H00804020&}A quiet moment{\\i0} before the journey.
                    Dialogue: 0,0:00:00.00,0:00:24.00,Song,,0,0,0,,{\\k300}Sing {\\k300}a{\\k1200}long
                    """
            }
            return "WEBVTT\n\n00:00.000 --> 00:24.000\n"
                + (path == "english"
                    ? "A quiet moment before the journey." : "Un momento de calma antes del viaje.")
        }
        func save(mediaID: String, chapterID: String, position: Double, duration: Double)
            async throws
        {
        }
    }

    struct StreamingPlayerTestRepository: PlayerRepository {
        private let embedded = LivePlayerRepository()
        func stream(chapterID: String) async throws -> (EpisodeStream, Double) {
            // Imported fixtures have no extension metadata; use their real
            // content route while keeping source choices deterministic.
            let path = "/content/1/\(chapterID)/video"
            return (
                EpisodeStream(
                    url: path,
                    sources: [
                        .init(label: "Fixture A", url: path),
                        .init(label: "Fixture B", url: path),
                    ], subtitles: [.init(lang: "English", url: "english")]), 8
            )
        }
        func request(path: String) async throws -> URLRequest {
            try await embedded.request(path: path)
        }
        func subtitle(path: String) async throws -> String {
            try await PlayerPreviewRepository().subtitle(path: path)
        }
        func save(mediaID: String, chapterID: String, position: Double, duration: Double)
            async throws
        {
            try await embedded.save(
                mediaID: mediaID, chapterID: chapterID, position: position, duration: duration)
        }
    }

    struct PlayerPreviewHost: View {
        private struct Presentation: Identifiable {
            let id = UUID()
            let model: PlayerViewModel
        }
        @State private var presentation: Presentation?
        @State private var failure: String?
        var body: some View {
            Text(failure ?? "Player closed")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black).foregroundStyle(.white)
                .fullScreenCover(item: $presentation) { value in
                    PlayerView(model: value.model)
                }
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--ui-testing-player-streaming") {
                        do {
                            try await Backend.shared.preparePlayerUITest()
                            if ProcessInfo.processInfo.arguments.contains(
                                "--ui-testing-player-signals")
                            {
                                // Network cancellation can deliver these to any native thread.
                                // Before the runtime fix, the first signal aborted the process.
                                raise(SIGPIPE)
                                raise(SIGXFSZ)
                            }
                            let player = PlayerViewModel(
                                title: "Player Fixture", mediaID: "1",
                                chapters: (1...3).map {
                                    Chapter(
                                        id: String($0), title: "Episode \($0)", number: Double($0),
                                        scanlator: nil, completed: false, downloaded: false)
                                }, chapterID: "1", repository: StreamingPlayerTestRepository())
                            player.autoplay = false
                            presentation = Presentation(model: player)
                        } catch {
                            failure = "Player fixture failed: \(error.localizedDescription)"
                            return
                        }
                    } else {
                        presentation = Presentation(model: .preview())
                    }
                }
        }
    }

    extension PlayerViewModel {
        static func preview() -> PlayerViewModel {
            let model = PlayerViewModel(
                title: "Dogulwang (Toukutsu Ou)", mediaID: "preview",
                chapters: (1...3).map {
                    Chapter(
                        id: "preview-\($0)", title: "Episode \($0)", number: Double($0),
                        scanlator: nil, completed: false, downloaded: false)
                }, chapterID: "preview-1", repository: PlayerPreviewRepository())
            model.autoplay = false
            return model
        }
    }
#endif

import AVFoundation
import SwiftUI
import UIKit

struct PlayerView: View {
    @State var model: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.skeletonStorageScope) private var skeletonStorage
    @AppStorage("preferences.animations") private var animations = true
    @AppStorage("player.autoplay") private var defaultAutoplay = true
    @AppStorage("player.speed") private var defaultSpeed = 1.0
    @AppStorage("player.subtitleScale") private var defaultSubtitleScale = 1.0
    @AppStorage("player.subtitleHeight") private var defaultSubtitleHeight = 9.0
    @AppStorage("player.subtitleBackground") private var defaultSubtitleBackground = false
    @AppStorage("player.autoplayNext") private var autoplayNext = true
    @AppStorage("player.autoSubtitles") private var autoSubtitles = true
    @AppStorage("player.subtitleLanguage") private var subtitleLanguage = ""
    @AppStorage("player.manualControls") private var manualControls = false
    @AppStorage("player.compactControls") private var compactControls = false
    @AppStorage("player.qualityScaling") private var qualityScaling = false
    @AppStorage("player.backgroundAudio") private var backgroundAudio = true
    @State private var pictureInPicture = PictureInPicture()
    @State private var nowPlaying = NowPlaying()
    @State private var backgrounded = false
    @State private var seekFlash: SeekFlash?
    private struct SeekFlash: Equatable { let seconds: Int; let leading: Bool; let id = UUID() }
    @State private var appliedDefaults = false
    @State private var controlsVisible = true
    @State private var panel: Panel?
    @State private var lastInteraction = Date()
    @State private var scrubbing = false
    @State private var scrubPosition = 0.0
    @State private var previousIdleTimer = false
    private let accent = Color(red: 122 / 255, green: 170 / 255, blue: 122 / 255)
    private typealias Panel = PlayerMenu.Kind

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                PlayerSurface(
                    player: model.player, qualityScaling: qualityScaling,
                    detached: backgrounded && !pictureInPicture.isActive,
                    pictureInPicture: pictureInPicture
                ).ignoresSafeArea()
                    .contentShape(Rectangle())
                    // Double-tap the edges to seek like other players; the centre
                    // toggles bars in manual mode and play/pause otherwise.
                    .gesture(
                        SpatialTapGesture(count: 2).onEnded { value in
                            doubleTap(at: value.location.x, width: geometry.size.width)
                        }.exclusively(before: TapGesture(count: 1).onEnded {
                            if !manualControls { toggleControls() }
                        }))
                    .accessibilityLabel("Video")
                    .accessibilityAction(named: "Show playback controls") { reveal() }
                    .accessibilityAction(named: "Back 10 seconds") { model.seek(model.position - 10) }
                    .accessibilityAction(named: "Forward 10 seconds") { model.seek(model.position + 10) }
                if let flash = seekFlash {
                    HStack {
                        if !flash.leading { Spacer() }
                        Label(flash.leading ? "−\(flash.seconds)s" : "+\(flash.seconds)s",
                              phosphor: flash.leading ? "ArrowCounterClockwise" : "ArrowClockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.horizontal, geometry.size.width * 0.12)
                        if flash.leading { Spacer() }
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .id(flash.id)
                }
                if !model.caption.isEmpty {
                    VStack {
                        Spacer()
                        Text(model.caption)
                            .font(.system(size: (landscape ? 18 : 16) * model.subtitleScale))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(
                                model.subtitleBackground ? Color.black.opacity(0.75) : .clear
                            )
                            .shadow(color: .black, radius: 2, y: 1)
                            .padding(.horizontal, 24)
                            .padding(
                                .bottom,
                                max(
                                    geometry.size.height * model.subtitleHeight / 100,
                                    controlsVisible ? (landscape ? 66 : 128) : 16))
                    }.allowsHitTesting(false)
                }
                if model.loading {
                    ContentSkeleton(style: .player)
                } else if model.buffering {
                    VStack {
                        Spacer()
                        SkeletonBlock(height: 4, radius: 2)
                            .skeletonMotion("Video is buffering")
                            .padding(.horizontal, 24).padding(.bottom, 100)
                    }.allowsHitTesting(false)
                }
                if let error = model.error {
                    VStack(spacing: 12) {
                        Text(error).multilineTextAlignment(.center).font(.subheadline)
                        Button("Try again") { Task { await model.load() } }
                            .frame(minHeight: 44).tint(accent)
                    }.padding(20).frame(maxWidth: 340).playerPanel()
                }
                if let marker = model.activeSkip, model.error == nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button { model.skip(marker) } label: {
                                Label(marker.label, phosphor: "SkipForward")
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.horizontal, 16).frame(minHeight: 44)
                                    .background(.black.opacity(0.7), in: Capsule())
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
                            }
                            .accessibilityIdentifier("player.skip")
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, controlsVisible ? (landscape ? 76 : 140) : 28)
                    }
                    .transition(.opacity)
                }
                if controlsVisible || model.error != nil {
                    VStack(spacing: 8) {
                        PlayerControls(
                            model: model, landscape: landscape, headerOnly: true,
                            scrubbing: $scrubbing, scrubPosition: $scrubPosition,
                            toggle: toggle, reveal: reveal, changeEpisode: changeEpisode,
                            dismiss: { dismiss() },
                            pictureInPicture: PictureInPicture.isSupported && pictureInPicture.isPossible
                                ? { pictureInPicture.toggle() } : nil)
                        if let panel {
                            HStack {
                                Spacer(minLength: 0)
                                PlayerMenu(
                                    model: model, panel: panel, close: { self.panel = nil },
                                    reveal: reveal, changeEpisode: changeEpisode
                                )
                                .frame(width: min(320, geometry.size.width - 24))
                                .frame(
                                    maxHeight: min(
                                        panelHeight(panel),
                                        max(
                                            120, geometry.size.height - (landscape ? 128 : 210))
                                    )
                                )
                                .playerPanel()
                            }
                        }
                        Spacer(minLength: 0)
                        if let notice = model.notice {
                            HStack {
                                Text(notice).font(.caption)
                                Button("Dismiss") { model.notice = nil }.frame(minHeight: 44)
                            }.padding(.horizontal, 12).playerPanel()
                        }
                        PlayerControls(
                            model: model, landscape: landscape || compactControls, headerOnly: false,
                            scrubbing: $scrubbing, scrubPosition: $scrubPosition,
                            toggle: toggle, reveal: reveal, changeEpisode: changeEpisode,
                            dismiss: { dismiss() })
                    }.padding(.horizontal, landscape ? 12 : 10)
                        .padding(.top, 8).padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(Color(white: 0.86))
            .font(.system(size: 13))
            .tint(accent)
            .buttonStyle(.plain)
            .preferredColorScheme(.dark)
            .statusBarHidden(landscape || !controlsVisible)
        }
        .recordActivity(
            entry: model.activityEntry,
            chapterID: model.chapterID, position: Int(max(0, model.position)),
            completed: model.duration > 0 && model.position >= model.duration - 1,
            active: model.playing && !model.buffering,
            valid: model.activityReady
        )
        .onChange(of: model.playing) { _, _ in if !manualControls { reveal() } }
        .onChange(of: model.episodeFinished) { _, finished in
            if finished && autoplayNext { changeEpisode(model.index + 1) }
        }
        .task(id: model.chapterID) {
            if !appliedDefaults {
                model.autoplay = defaultAutoplay
                model.autoplayNext = autoplayNext
                model.autoSubtitles = autoSubtitles
                model.subtitleLanguage = subtitleLanguage
                model.speed = Float(min(2, max(0.75, defaultSpeed)))
                model.subtitleScale = min(2, max(0.75, defaultSubtitleScale))
                model.subtitleHeight = min(20, max(3, defaultSubtitleHeight))
                model.subtitleBackground = defaultSubtitleBackground
                appliedDefaults = true
            }
            await model.load()
        }
        .task {
            previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            nowPlaying.attach(
                toggle: { model.togglePlayback() },
                seek: { model.seek($0) },
                skip: { model.seek(model.position + $0) },
                episode: { changeEpisode(model.index + $0) })
            while !Task.isCancelled {
                if !scrubbing { await model.tick() }
                nowPlaying.update(
                    title: model.title, episode: model.episodeLabel, position: model.position,
                    duration: model.duration, rate: model.speed, playing: model.playing)
                if !manualControls && model.playing && !model.buffering && panel == nil && !scrubbing && !voiceOver
                    && Date().timeIntervalSince(lastInteraction) > 4
                {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        controlsVisible = false
                    }
                }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
        ) { note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            if type == .ended {
                let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map(AVAudioSession.InterruptionOptions.init) ?? []
                if options.contains(.shouldResume), !model.playing { model.togglePlayback() }
                return
            }
            model.player.pause()
            model.playing = false
            reveal()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                backgrounded = false
                model.isActive = true
            case .background:
                model.saveSnapshot()
                // Keep playing with the screen off or in another app (audio, or PiP).
                if (backgroundAudio || pictureInPicture.isActive) && model.playing {
                    backgrounded = true
                } else {
                    model.isActive = false
                    model.player.pause()
                    model.playing = false
                    reveal()
                }
            default:
                break
            }
        }
        // Remember what the viewer picks, like desktop does.
        .onChange(of: model.subtitleScale) { _, value in defaultSubtitleScale = value }
        .onChange(of: model.subtitleHeight) { _, value in defaultSubtitleHeight = value }
        .onChange(of: model.subtitleBackground) { _, value in defaultSubtitleBackground = value }
        .onChange(of: model.subtitleIndex) { _, index in
            if let index, let track = model.stream?.subtitles[safe: index] { subtitleLanguage = track.lang }
        }
        .onDisappear {
            nowPlaying.detach()
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimer
            model.stop()
            model.saveSnapshot()
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        }
    }

    private func panelHeight(_ panel: Panel) -> CGFloat {
        let rows: Int
        switch panel {
        case .subtitles: rows = 4 + max(1, model.stream?.subtitles.count ?? 0)
        case .episodes: rows = model.chapters.count
        case .speed: rows = 6
        case .more: rows = 2 + (model.stream?.sources.count ?? 0) + 3
        }
        return CGFloat(rows * 44 + 56)
    }
    private func toggleControls() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            controlsVisible.toggle()
            panel = nil
            lastInteraction = Date()
        }
    }

    private func doubleTap(at x: CGFloat, width: CGFloat) {
        let zone = width > 0 ? x / width : 0.5
        guard zone < 0.35 || zone > 0.65 else {
            if manualControls { toggleControls() } else { model.togglePlayback() }
            return
        }
        let back = zone < 0.35
        model.seek(model.position + (back ? -10 : 10))
        let flash = SeekFlash(seconds: 10, leading: back)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { seekFlash = flash }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            if seekFlash == flash { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { seekFlash = nil } }
        }
    }

    private func toggle(_ value: Panel) {
        panel = panel == value ? nil : value
        reveal()
    }
    private func reveal() {
        controlsVisible = true
        lastInteraction = Date()
    }
    private func changeEpisode(_ index: Int) {
        guard model.chapters.indices.contains(index), model.chapters[index].id != model.chapterID
        else {
            return
        }
        model.player.pause()
        model.playing = false
        panel = nil
        reveal()
        model.saveSnapshot()
        model.chapterID = model.chapters[index].id
    }
}

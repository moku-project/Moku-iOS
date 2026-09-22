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
                PlayerSurface(player: model.player).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            controlsVisible.toggle()
                            panel = nil
                            lastInteraction = Date()
                        }
                    }
                    .accessibilityLabel("Video")
                    .accessibilityAction(named: "Show playback controls") { reveal() }
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
                if controlsVisible || model.error != nil {
                    VStack(spacing: 8) {
                        PlayerControls(
                            model: model, landscape: landscape, headerOnly: true,
                            scrubbing: $scrubbing, scrubPosition: $scrubPosition,
                            toggle: toggle, reveal: reveal, changeEpisode: changeEpisode,
                            dismiss: { dismiss() })
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
                            model: model, landscape: landscape, headerOnly: false,
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
            entry: HomeEntry(
                id: model.mediaID, title: model.title, media: "Anime",
                chapters: model.chapters.map { HomeChapter(id: $0.id, title: $0.label) }),
            chapterID: model.chapterID, position: Int(max(0, model.position)),
            completed: model.duration > 0 && model.position >= model.duration - 1,
            active: model.playing && !model.buffering,
            valid: model.activityReady
        )
        .onChange(of: model.playing) { _, _ in reveal() }
        .task(id: model.chapterID) {
            let visits = SkeletonVisits.shared
            let key = "\(skeletonStorage):player-\(model.chapterID):\(visits.generation)"
            let delay = !reduceMotion && animations && !visits.contains(key)
            await model.load(minimumLoadingDuration: delay ? .seconds(SkeletonTiming.cycle) : .zero)
            if !Task.isCancelled && model.error == nil { visits.complete(key) }
        }
        .task {
            previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            while !Task.isCancelled {
                if !scrubbing { await model.tick() }
                if model.playing && !model.buffering && panel == nil && !scrubbing && !voiceOver
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
        ) { _ in
            model.player.pause()
            model.playing = false
            reveal()
        }
        .onChange(of: scenePhase) { _, phase in
            model.isActive = phase == .active
            if phase != .active {
                model.player.pause()
                model.playing = false
                reveal()
                model.saveSnapshot()
            }
        }
        .onDisappear {
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
        case .more: rows = 2 + (model.stream?.sources.count ?? 0) + 1
        }
        return CGFloat(rows * 44 + 56)
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

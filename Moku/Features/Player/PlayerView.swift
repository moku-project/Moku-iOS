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

    /// Cues sharing a screen position, each in its own ASS style.
    @ViewBuilder private func captionGroup(_ position: SubtitleCue.Position, landscape: Bool, picture: CGFloat, time: Double) -> some View {
        let cues = model.captions.filter { $0.position == position && $0.anchor == nil }
        if !cues.isEmpty {
            VStack(spacing: 2) {
                ForEach(Array(cues.enumerated()), id: \.offset) { _, cue in
                    caption(cue, landscape: landscape, picture: picture, time: time)
                        .opacity(cue.opacity(at: time))
                        .frame(maxWidth: .infinity, alignment: Self.alignment(cue.horizontal))
                }
            }
        }
    }

    /// `\pos` cues, pinned to their point in the picture by their `\an` corner.
    private func anchoredCaptions(in size: CGSize, landscape: Bool, time: Double) -> some View {
        let picture = Self.pictureRect(in: size)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(model.captions.enumerated()), id: \.offset) { _, cue in
                if let anchor = cue.anchor(at: time) {
                    caption(cue, landscape: landscape, picture: picture.height, time: time)
                        .opacity(cue.opacity(at: time))
                        .fixedSize()
                        .frame(width: 0, height: 0, alignment: Self.corner(cue))
                        .position(x: picture.minX + anchor.x * picture.width, y: picture.minY + anchor.y * picture.height)
                        .mask { Self.clipMask(cue, picture: picture, size: size) }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Text or a `\p` shape, then `\fscx`/`\fscy` and `\frz` around the `\an` corner.
    private func caption(_ cue: SubtitleCue, landscape: Bool, picture: CGFloat, time: Double) -> some View {
        let corner = Self.unitPoint(Self.corner(cue))
        return Group {
            if cue.shape.isEmpty {
                textCaption(cue, landscape: landscape, picture: picture, time: time)
            } else {
                shapeCaption(cue, picture: picture, time: time)
            }
        }
        .blur(radius: min(3, CGFloat(cue.blur) * picture))
        .scaleEffect(x: cue.scaleX, y: cue.scaleY, anchor: corner)
        // \frx / \fry tilt in 3D; ASS turns counter-clockwise for positive \frz, SwiftUI clockwise.
        .rotation3DEffect(.degrees(cue.rotationX), axis: (x: 1, y: 0, z: 0), anchor: corner)
        .rotation3DEffect(.degrees(-cue.rotationY), axis: (x: 0, y: 1, z: 0), anchor: corner)
        .rotationEffect(.degrees(-cue.rotation), anchor: corner)
    }

    /// A vector drawing, filled with the primary colour and bordered like text.
    private func shapeCaption(_ cue: SubtitleCue, picture: CGFloat, time: Double) -> some View {
        let size = CGSize(width: picture * 16 / 9, height: picture)
        var path = Path()
        for command in cue.shape {
            func scaled(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * size.width, y: point.y * size.height) }
            switch command {
            case .move(let point): path.move(to: scaled(point))
            case .line(let point): path.addLine(to: scaled(point))
            case .curve(let one, let two, let end): path.addCurve(to: scaled(end), control1: scaled(one), control2: scaled(two))
            case .close: path.closeSubpath()
            }
        }
        let bounds = path.boundingRect
        let placed = path.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        let width = CGFloat(cue.outlineWidth(at: time)) * picture
        return ZStack {
            placed.fill(cue.color(at: time).map(Self.color) ?? .white)
            if let outline = cue.outline, width > 0 {
                placed.stroke(Self.color(outline), lineWidth: min(4, width))
            }
        }
        .frame(width: max(1, bounds.width), height: max(1, bounds.height))
        .opacity(cue.alpha(at: time))
        .accessibilityHidden(true)
    }

    /// `\clip` keeps the inside of its rectangle; `\iclip` keeps the outside.
    @ViewBuilder static func clipMask(_ cue: SubtitleCue, picture: CGRect, size: CGSize) -> some View {
        if !cue.clipShape.isEmpty {
            // A drawing clip, in picture coordinates.
            Path { path in
                if cue.clipInverted { path.addRect(CGRect(origin: .zero, size: size)) }
                func scaled(_ point: CGPoint) -> CGPoint {
                    CGPoint(x: picture.minX + point.x * picture.width, y: picture.minY + point.y * picture.height)
                }
                for command in cue.clipShape {
                    switch command {
                    case .move(let point): path.move(to: scaled(point))
                    case .line(let point): path.addLine(to: scaled(point))
                    case .curve(let one, let two, let end): path.addCurve(to: scaled(end), control1: scaled(one), control2: scaled(two))
                    case .close: path.closeSubpath()
                    }
                }
                path.closeSubpath()
            }
            .fill(style: FillStyle(eoFill: true))
        } else if let clip = cue.clip {
            let rect = CGRect(
                x: picture.minX + clip.minX * picture.width, y: picture.minY + clip.minY * picture.height,
                width: clip.width * picture.width, height: clip.height * picture.height)
            Path { path in
                if cue.clipInverted { path.addRect(CGRect(origin: .zero, size: size)) }
                path.addRect(rect)
            }
            .fill(style: FillStyle(eoFill: true))
        } else {
            Rectangle()
        }
    }

    private static func unitPoint(_ alignment: Alignment) -> UnitPoint {
        switch alignment {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        default: .center
        }
    }

    private func textCaption(_ cue: SubtitleCue, landscape: Bool, picture: CGFloat, time: Double) -> some View {
        // libass sizes text against the picture height; plain cues keep the app's size.
        // A small portrait picture would make script sizes unreadable, so they have a floor.
        let points = (cue.size(at: time).map { min(64, max(landscape ? 16 : 14, CGFloat($0) * picture)) } ?? (landscape ? 18 : 16))
            * model.subtitleScale
        // Style fonts by name or family, including fonts embedded in the file.
        let font = cue.fontName.flatMap { SubtitleFonts.font(named: $0, size: points) }.map { Font($0 as CTFont) }
            ?? .system(size: points)
        let primary = cue.color(at: time).map(Self.color) ?? .white
        // Karaoke: sung syllables take the primary colour, the rest the secondary.
        let words = cue.karaoke.isEmpty
            ? Text(cue.text).foregroundStyle(primary)
            : cue.karaoke.indices.reduce(Text("")) { line, index in
                line + Text(cue.karaoke[index].text)
                    .foregroundStyle(cue.sung(index, at: time) ? primary : cue.secondary.map(Self.color) ?? Color(white: 0.6))
            }
        let text = words.font(font).fontWeight(cue.bold ? .bold : .regular).italic(cue.italic)
            .multilineTextAlignment(Self.textAlignment(cue.horizontal))
        let width = min(4, max(1, CGFloat(cue.outlineWidth(at: time)) * picture))
        // A border from four stacked zero-blur shadows, close to libass's outline.
        // Shadows add no extra text, so VoiceOver reads each line once.
        let border = cue.outline.map(Self.color) ?? .clear
        return text
            .opacity(cue.alpha(at: time))
            .shadow(color: border, radius: 0, x: width, y: 0)
            .shadow(color: border, radius: 0, x: -width, y: 0)
            .shadow(color: border, radius: 0, x: 0, y: width)
            .shadow(color: border, radius: 0, x: 0, y: -width)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(model.subtitleBackground ? Color.black.opacity(0.75) : .clear)
            // \shad: a hard drop shadow of the bordered text; plain cues keep a soft one.
            .shadow(
                color: cue.shadowDepth > 0 ? Self.color(cue.shadowColor ?? 0) : cue.outline == nil ? .black : .clear,
                radius: cue.shadowDepth > 0 ? 0 : 2,
                x: cue.shadowDepth > 0 ? min(4, CGFloat(cue.shadowDepth) * picture) : 0,
                y: cue.shadowDepth > 0 ? min(4, CGFloat(cue.shadowDepth) * picture) : 1)
    }

    private func captionLayer(size: CGSize, landscape: Bool, time: Double) -> some View {
        let picture = Self.pictureRect(in: size).height
        return ZStack {
        anchoredCaptions(in: size, landscape: landscape, time: time)
        VStack(spacing: 0) {
            captionGroup(.top, landscape: landscape, picture: picture, time: time)
                .padding(.top, controlsVisible ? (landscape ? 66 : 110) : 24)
            Spacer()
            captionGroup(.middle, landscape: landscape, picture: picture, time: time)
            Spacer()
            captionGroup(.bottom, landscape: landscape, picture: picture, time: time)
                .padding(
                    .bottom,
                    max(size.height * model.subtitleHeight / 100, controlsVisible ? (landscape ? 66 : 128) : 16))
        }
        .padding(.horizontal, 24)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    /// The 16:9 picture as the player fits it in the view.
    static func pictureRect(in size: CGSize) -> CGRect {
        let width = min(size.width, size.height * 16 / 9)
        let height = width * 9 / 16
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private static func color(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    private static func alignment(_ horizontal: SubtitleCue.Horizontal) -> Alignment {
        switch horizontal {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    private static func textAlignment(_ horizontal: SubtitleCue.Horizontal) -> TextAlignment {
        switch horizontal {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    /// The corner or edge of the text that sits on the `\pos` point (numpad `\an`).
    private static func corner(_ cue: SubtitleCue) -> Alignment {
        switch (cue.position, cue.horizontal) {
        case (.top, .left): .topLeading
        case (.top, .center): .top
        case (.top, .right): .topTrailing
        case (.middle, .left): .leading
        case (.middle, .center): .center
        case (.middle, .right): .trailing
        case (.bottom, .left): .bottomLeading
        case (.bottom, .center): .bottom
        case (.bottom, .right): .bottomTrailing
        }
    }

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
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.horizontal, geometry.size.width * 0.12)
                        if flash.leading { Spacer() }
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .id(flash.id)
                }
                if !model.captions.isEmpty {
                    if model.captions.contains(where: \.isAnimated) {
                        // \fad and \move need the player clock every frame, not the polled position.
                        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.playing)) { _ in
                            let clock = model.player.currentTime().seconds
                            captionLayer(size: geometry.size, landscape: landscape, time: clock.isFinite ? clock : model.position)
                        }
                    } else {
                        captionLayer(size: geometry.size, landscape: landscape, time: model.position)
                    }
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
                                    .font(.subheadline.weight(.semibold))
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
            .font(.footnote)
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

import AVFoundation
import SwiftUI

struct PlayerControls: View {
    @AppStorage("keybinds.player.play") private var playKey = " "
    @AppStorage("keybinds.player.previous") private var previousKey = "["
    @AppStorage("keybinds.player.next") private var nextKey = "]"
    @Bindable var model: PlayerViewModel
    let landscape: Bool
    @Binding var scrubbing: Bool
    @Binding var scrubPosition: Double
    let reveal: () -> Void
    let changeEpisode: (Int) -> Void
    let dismiss: () -> Void
    var pictureInPicture: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            centre
            Spacer(minLength: 0)
            bottomBar
        }
        .padding(.horizontal, landscape ? 20 : 14)
        .padding(.vertical, landscape ? 10 : 6)
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 10) {
            glassIcon("xmark", label: "Close player", id: "player.close") {
                model.stop()
                dismiss()
            }
            episodeMenu
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                AirPlayButton().frame(width: 40, height: 40)
                if let pictureInPicture {
                    plainIcon(
                        "pip.enter", label: "Picture in Picture", id: "player.pip",
                        action: pictureInPicture)
                }
                plainIcon(
                    model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: model.muted ? "Unmute" : "Mute", id: "player.mute"
                ) { model.toggleMute() }
                subtitleMenu
                optionsMenu
            }
            .padding(.horizontal, 4)
            .glassSurface(Capsule())
        }
    }

    private var episodeMenu: some View {
        Menu {
            // Buttons, not a Picker: a Picker binding writes back when the episode changes underneath it.
            ForEach(Array(model.chapters.enumerated()), id: \.element.id) { index, chapter in
                Button {
                    changeEpisode(index)
                } label: {
                    let title =
                        "Ep. \(chapter.number?.formatted() ?? String(index + 1)) — \(chapter.title ?? "Episode")"
                    if index == model.index {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 3) {
                    Text(model.episodeLabel)
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Choose episode")
        .accessibilityValue(model.episodeLabel)
        .accessibilityIdentifier("player.episodes")
    }

    private var subtitleMenu: some View {
        Menu {
            Picker(
                "Subtitles",
                selection: Binding(
                    get: { model.subtitleIndex ?? -1 },
                    set: { value in Task { await model.selectSubtitle(value < 0 ? nil : value) } }
                )
            ) {
                Text("Off").tag(-1)
                ForEach(Array((model.stream?.subtitles ?? []).enumerated()), id: \.offset) {
                    index, track in
                    Text(track.lang).tag(index)
                }
            }
            .pickerStyle(.inline)
            Menu("Text Size") {
                Picker("Text Size", selection: $model.subtitleScale) {
                    ForEach([0.75, 0.9, 1, 1.1, 1.25, 1.5, 2], id: \.self) {
                        Text("\(Int((($0) * 100).rounded()))%").tag($0)
                    }
                }
            }
            Menu("Position") {
                Picker("Position", selection: $model.subtitleHeight) {
                    Text("Low").tag(3.0)
                    Text("Default").tag(9.0)
                    Text("Raised").tag(18.0)
                    Text("High").tag(30.0)
                }
            }
            Toggle("Background", isOn: $model.subtitleBackground)
        } label: {
            Image(
                systemName: model.subtitleIndex == nil ? "captions.bubble" : "captions.bubble.fill"
            )
            .font(.body.weight(.medium)).frame(width: 40, height: 40)
        }
        .accessibilityLabel("Subtitles")
        .accessibilityValue(subtitleLabel)
        .accessibilityIdentifier("player.subtitles")
    }

    private var optionsMenu: some View {
        Menu {
            if let stream = model.stream, !stream.sources.isEmpty {
                Picker(
                    "Source",
                    selection: Binding(
                        get: { model.sourceIndex ?? -1 },
                        set: { value in Task { await model.changeSource(value) } }
                    )
                ) {
                    ForEach(Array(stream.sources.enumerated()), id: \.offset) { index, source in
                        Text(source.label).tag(index)
                    }
                }
                .pickerStyle(.inline)
            }
            Section { Text(model.streamInfo) }
        } label: {
            Image(systemName: "ellipsis.circle").font(.body.weight(.medium)).frame(
                width: 40, height: 40)
        }
        .accessibilityLabel("Player options")
        .accessibilityIdentifier("player.options")
    }

    // MARK: Centre

    private var centre: some View {
        HStack(spacing: landscape ? 56 : 36) {
            glassIcon("gobackward.10", label: "Back 10 seconds", id: "player.back", size: 52) {
                model.seek(model.position - 10)
            }
            ZStack {
                glassIcon(
                    model.playing ? "pause.fill" : "play.fill",
                    label: model.playing ? "Pause" : "Play",
                    id: "player.play", size: 72
                ) { model.togglePlayback() }
                .disabled(model.loading || model.player.currentItem == nil || model.error != nil)
                .keyboardShortcut(shortcut(playKey))
                .opacity(model.loading || model.buffering ? 0 : 1)
                // The spinner takes the play button's place while video loads, as in the system player.
                if model.loading || model.buffering {
                    ProgressView().controlSize(.large).tint(.white).allowsHitTesting(false)
                }
            }
            glassIcon("goforward.10", label: "Forward 10 seconds", id: "player.forward", size: 52) {
                model.seek(model.position + 10)
            }
        }
    }

    // MARK: Bottom

    private var bottomBar: some View {
        VStack(spacing: 2) {
            timeline
            HStack(spacing: 12) {
                Text(PlayerViewModel.time(scrubbing ? scrubPosition : model.position))
                Spacer()
                plainIcon("backward.end.fill", label: "Previous episode", id: "player.previous") {
                    changeEpisode(model.index - 1)
                }
                .disabled(model.index == 0)
                .keyboardShortcut(shortcut(previousKey))
                speedMenu
                plainIcon("forward.end.fill", label: "Next episode", id: "player.next") {
                    changeEpisode(model.index + 1)
                }
                .disabled(model.index + 1 >= model.chapters.count)
                .keyboardShortcut(shortcut(nextKey))
                Spacer()
                Text(
                    "-"
                        + PlayerViewModel.time(
                            max(0, model.duration - (scrubbing ? scrubPosition : model.position))))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var speedMenu: some View {
        Menu {
            Picker(
                "Playback Speed",
                selection: Binding(get: { Double(model.speed) }, set: { model.setSpeed(Float($0)) })
            ) {
                ForEach([0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) {
                    Text("\($0.formatted())×").tag($0)
                }
            }
        } label: {
            Text("\(model.speed.formatted())×").font(.caption.weight(.semibold).monospacedDigit())
                .frame(minWidth: 44, minHeight: 40)
        }
        .accessibilityLabel("Playback speed")
        .accessibilityValue("\(model.speed.formatted()) times")
        .accessibilityIdentifier("player.speed")
    }

    private var timeline: some View {
        PlayerTimeline(
            value: scrubbing ? scrubPosition : model.position, duration: model.duration,
            changed: { scrubPosition = $0 },
            editing: { editing in
                if editing { scrubPosition = model.position }
                scrubbing = editing
                reveal()
                if !editing { model.seek(scrubPosition) }
            }
        )
        .frame(minHeight: 44)
        .overlay { skipMarkers }
    }

    /// Intro, outro and recap ranges drawn on the track.
    private var skipMarkers: some View {
        GeometryReader { proxy in
            let inset = 6.0
            let width = max(0, proxy.size.width - inset * 2)
            let total = model.duration
            if total.isFinite, total > 0 {
                ForEach(Array(model.skipMarkers.enumerated()), id: \.offset) { _, marker in
                    let start = min(1, max(0, marker.start / total))
                    let end = min(1, max(start, marker.end / total))
                    Capsule()
                        .fill(NavigationStyle.accent.opacity(0.8))
                        .frame(width: max(2, (end - start) * width), height: 3)
                        .position(x: inset + (start + end) / 2 * width, y: proxy.size.height / 2)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Pieces

    private func glassIcon(
        _ symbol: String, label: String, id: String, size: CGFloat = 44,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            reveal()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .glassSurface(Circle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func plainIcon(
        _ symbol: String, label: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            reveal()
            action()
        } label: {
            Image(systemName: symbol).font(.body.weight(.medium)).frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func shortcut(_ value: String) -> KeyboardShortcut? {
        value.first.map { KeyboardShortcut(KeyEquivalent($0), modifiers: []) }
    }

    private var subtitleLabel: String {
        guard let index = model.subtitleIndex, let track = model.stream?.subtitles[safe: index]
        else { return "Off" }
        return track.lang
    }
}

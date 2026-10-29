import AVFoundation
import SwiftUI

struct PlayerControls: View {
    @AppStorage("keybinds.player.play") private var playKey = " "
    @AppStorage("keybinds.player.previous") private var previousKey = "["
    @AppStorage("keybinds.player.next") private var nextKey = "]"
    let model: PlayerViewModel
    let landscape: Bool
    let headerOnly: Bool
    @Binding var scrubbing: Bool
    @Binding var scrubPosition: Double
    let toggle: (PlayerMenu.Kind) -> Void
    let reveal: () -> Void
    let changeEpisode: (Int) -> Void
    let dismiss: () -> Void
    var pictureInPicture: (() -> Void)? = nil
    var body: some View {
        if headerOnly { header(landscape: landscape) } else { transport(landscape: landscape) }
    }
    private func shortcut(_ value: String) -> KeyboardShortcut? {
        value.first.map { KeyboardShortcut(KeyEquivalent($0), modifiers: []) }
    }
    private func header(landscape: Bool) -> some View {
        HStack(spacing: 0) {
            icon("X", label: "Close player", id: "player.close") {
                model.stop()
                dismiss()
            }
            separator
            if landscape {
                icon("CaretLeft", label: "Previous episode") { changeEpisode(model.index - 1) }
                    .disabled(model.index == 0)
            }
            VStack(alignment: .leading, spacing: 1) {
                if landscape {
                    HStack(spacing: 8) {
                        Text(model.title).lineLimit(1)
                        Text("/").foregroundStyle(.secondary)
                        episodeButton
                    }
                } else {
                    Button {
                        toggle(.episodes)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.title).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(model.episodeLabel)
                                PhosphorIcon("CaretDown", size: 11)
                            }.foregroundStyle(.secondary).font(.caption)
                        }.frame(minHeight: 44)
                    }.accessibilityLabel("Choose episode").accessibilityIdentifier(
                        "player.episodes")
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
            if landscape {
                icon("CaretRight", label: "Next episode") { changeEpisode(model.index + 1) }
                    .disabled(model.index + 1 >= model.chapters.count)
            }
            if let pictureInPicture {
                icon("PictureInPicture", label: "Picture in Picture", id: "player.pip") { pictureInPicture() }
            }
            AirPlayButton().frame(width: 44, height: 44)
            Button {
                toggle(.subtitles)
            } label: {
                HStack(spacing: 5) {
                    PhosphorIcon("ClosedCaptioning", size: 17)
                    if landscape {
                        Text(subtitleLabel).font(.caption.monospacedDigit()).lineLimit(
                            1)
                    }
                }.frame(minWidth: 44, minHeight: 44).padding(.horizontal, landscape ? 8 : 0)
            }.accessibilityLabel("Subtitles").accessibilityValue(subtitleLabel)
                .accessibilityIdentifier("player.subtitles")
            separator
            icon("DotsThree", label: "Player options", id: "player.options") { toggle(.more) }
        }.padding(.horizontal, 4).padding(.vertical, 2).playerPanel()
    }

    private var episodeButton: some View {
        Button {
            toggle(.episodes)
        } label: {
            HStack(spacing: 4) {
                Text(model.episodeLabel)
                PhosphorIcon("CaretDown", size: 11)
            }.foregroundStyle(.secondary).frame(minHeight: 44)
        }.accessibilityLabel("Choose episode").accessibilityIdentifier("player.episodes")
    }

    private func transport(landscape: Bool) -> some View {
        VStack(spacing: 0) {
            if !landscape {
                timeline
                HStack {
                    Text(PlayerViewModel.time(scrubbing ? scrubPosition : model.position))
                    Spacer()
                    Text(PlayerViewModel.time(model.duration))
                }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
            HStack(spacing: 0) {
                icon("SkipBack.fill", label: "Previous episode", id: "player.previous") {
                    changeEpisode(model.index - 1)
                }
                .disabled(model.index == 0)
                .keyboardShortcut(shortcut(previousKey))
                icon(
                    model.playing ? "Pause.fill" : "Play.fill",
                    label: model.playing ? "Pause" : "Play", id: "player.play"
                ) {
                    model.togglePlayback()
                }.disabled(model.loading || model.player.currentItem == nil || model.error != nil)
                    .keyboardShortcut(shortcut(playKey))
                icon("SkipForward.fill", label: "Next episode", id: "player.next") {
                    changeEpisode(model.index + 1)
                }
                .disabled(model.index + 1 >= model.chapters.count)
                .keyboardShortcut(shortcut(nextKey))
                separator
                if landscape {
                    timeline.padding(.horizontal, 8)
                    Text(
                        "\(PlayerViewModel.time(scrubbing ? scrubPosition : model.position)) / \(PlayerViewModel.time(model.duration))"
                    )
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .fixedSize().padding(.horizontal, 6)
                } else {
                    Spacer()
                }
                Button {
                    toggle(.speed)
                } label: {
                    Text("\(model.speed.formatted())×").font(.caption.monospacedDigit())
                        .frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Playback speed").accessibilityValue(
                    "\(model.speed.formatted()) times"
                )
                .accessibilityIdentifier("player.speed")
                icon(
                    model.muted ? "SpeakerSimpleX" : "SpeakerSimpleHigh",
                    label: model.muted ? "Unmute" : "Mute", id: "player.mute"
                ) {
                    model.toggleMute()
                }
            }
        }.padding(.horizontal, 6).padding(.vertical, 4).playerPanel()
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
        ).frame(minHeight: 44)
    }

    private func icon(_ name: String, label: String, id: String = "", action: @escaping () -> Void)
        -> some View
    {
        Button {
            reveal()
            action()
        } label: {
            PhosphorIcon(name, size: 18).frame(width: 44, height: 44).contentShape(Rectangle())
        }.accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private var separator: some View { Color.white.opacity(0.1).frame(width: 1, height: 20) }
    private var subtitleLabel: String {
        guard let index = model.subtitleIndex, let stream = model.stream,
            stream.subtitles.indices.contains(index)
        else { return "Off" }
        return stream.subtitles[index].lang
    }

}

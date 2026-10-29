import SwiftUI

struct PlayerMenu: View {
    enum Kind { case subtitles, episodes, speed, more }
    @Bindable var model: PlayerViewModel
    let panel: Kind
    let close: () -> Void
    let reveal: () -> Void
    let changeEpisode: (Int) -> Void
    private let accent = Color(red: 122 / 255, green: 170 / 255, blue: 122 / 255)
    var body: some View { panelContent(panel) }
    @ViewBuilder private func panelContent(_ panel: Kind) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text(panelTitle(panel)).font(.subheadline.weight(.semibold))
                    Spacer()
                    icon("X", label: "Close menu", id: "player.panel.close") {
                        close()
                        reveal()
                    }
                }.padding(.leading, 12)
                switch panel {
                case .subtitles:
                    row("Off", selected: model.subtitleIndex == nil) {
                        Task { await model.selectSubtitle(nil) }
                    }
                    if let stream = model.stream {
                        ForEach(Array(stream.subtitles.enumerated()), id: \.offset) {
                            index, subtitle in
                            row(subtitle.lang, selected: model.subtitleIndex == index) {
                                Task { await model.selectSubtitle(index) }
                            }
                        }
                        if stream.subtitles.isEmpty {
                            Text("No subtitle tracks available").font(.caption).foregroundStyle(
                                .secondary
                            )
                            .padding(12)
                        }
                    }
                    Divider().padding(.horizontal, 10)
                    stepper(
                        "Size", value: $model.subtitleScale, step: 0.1, bounds: 0.5...2.5,
                        label: "\(Int((model.subtitleScale * 100).rounded()))%")
                    stepper(
                        "Position", value: $model.subtitleHeight, step: 3, bounds: 0...45,
                        label: "\(Int(model.subtitleHeight))%")
                    Toggle("Background", isOn: $model.subtitleBackground)
                        .font(.footnote).padding(.horizontal, 12).frame(minHeight: 44)
                case .episodes:
                    ForEach(Array(model.chapters.enumerated()), id: \.element.id) {
                        index, chapter in
                        row(
                            "Ep. \(chapter.number?.formatted() ?? String(index + 1)) — \(chapter.title ?? "Episode")",
                            selected: chapter.id == model.chapterID
                        ) { changeEpisode(index) }
                    }
                case .speed:
                    ForEach([0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { value in
                        row("\(value.formatted())×", selected: model.speed == Float(value)) {
                            model.setSpeed(Float(value))
                            close()
                            reveal()
                        }
                    }
                case .more:
                    row("Back 10 seconds") {
                        model.seek(model.position - 10)
                        reveal()
                    }
                    row("Forward 10 seconds") {
                        model.seek(model.position + 10)
                        reveal()
                    }
                    if let stream = model.stream, !stream.sources.isEmpty {
                        Text("Source").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        ForEach(Array(stream.sources.enumerated()), id: \.offset) { index, source in
                            row(source.label, selected: model.sourceIndex == index) {
                                Task { await model.changeSource(index) }
                                close()
                                reveal()
                            }
                        }
                    }
                    // Desktop "Stream info".
                    Text("Stream").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    Text(model.streamInfo).font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Stream: \(model.streamInfo)")
                }
            }.padding(4)
        }
    }

    private func stepper(
        _ title: String, value: Binding<Double>, step: Double, bounds: ClosedRange<Double>,
        label: String
    ) -> some View {
        HStack(spacing: 0) {
            Text(title).padding(.leading, 12)
            Spacer()
            icon("Minus", label: "Decrease \(title)") {
                value.wrappedValue = max(bounds.lowerBound, value.wrappedValue - step)
            }
            Text(label).font(.caption2.monospacedDigit()).frame(minWidth: 38)
            icon("Plus", label: "Increase \(title)") {
                value.wrappedValue = min(bounds.upperBound, value.wrappedValue + step)
            }
        }
    }

    private func row(_ title: String, selected: Bool = false, action: @escaping () -> Void)
        -> some View
    {
        Button {
            reveal()
            action()
        } label: {
            HStack {
                Text(title).multilineTextAlignment(.leading)
                Spacer()
                if selected { PhosphorIcon("Check", size: 16) }
            }.foregroundStyle(selected ? accent : Color(white: 0.86))
                .padding(.horizontal, 12).frame(minHeight: 44)
        }.accessibilityAddTraits(selected ? .isSelected : [])
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
    private func panelTitle(_ panel: Kind) -> String {
        switch panel {
        case .subtitles: "Subtitles"
        case .episodes: "Episodes"
        case .speed: "Playback speed"
        case .more: "Player options"
        }
    }

}

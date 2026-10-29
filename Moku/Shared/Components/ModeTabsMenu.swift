import SwiftUI

struct ModeTabsMenu: View {
    @AppStorage("preferences.modeTabs") private var savedModes = ""
    @AppStorage("preferences.animations") private var animations = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(OverflowMenuPresentation.self) private var presentation: OverflowMenuPresentation?
    @State private var dragging: ContentMode?
    @State private var editing = false
    @State private var dragStartIndex = 0
    @State private var dragOffset: CGFloat = 0
    private var configuration: ModeTabConfiguration { ModeTabConfiguration(storage: savedModes) }
    private var motion: Animation? { reduceMotion || !animations ? nil : .easeInOut(duration: 0.18) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Modes").font(.headline)
                Spacer()
                Button { presentation?.dismiss() } label: {
                    PhosphorIcon("X", size: 16).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close modes")
                .accessibilityIdentifier("modes.close")
            }.padding(.leading, 10)
            HStack {
                MenuSection("Pinned")
                Spacer()
                Button(editing ? "Done" : "Edit") { editing.toggle() }
                    .font(.subheadline).foregroundStyle(NavigationStyle.accent)
                    .frame(width: 60, height: 44).buttonStyle(.plain)
                    .accessibilityIdentifier("modes.edit")
            }
            ForEach(configuration.visible) { mode in
                HStack(spacing: 8) {
                    modeLabel(mode)
                    Spacer(minLength: 0)
                    if mode != .all {
                        if editing {
                            Button { toggle(mode) } label: {
                                PhosphorIcon("X", size: 16).frame(width: 36, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Hide \(mode.title)")
                            .accessibilityIdentifier("modes.visible.\(mode.rawValue)")
                        }
                        PhosphorIcon("List", size: 18)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                                .onChanged { value in drag(mode, translation: value.translation.height) }
                                .onEnded { _ in
                                    withAnimation(motion) { dragging = nil; dragOffset = 0 }
                                })
                            .accessibilityHidden(false)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Reorder \(mode.title)")
                            .accessibilityIdentifier("modes.reorder.\(mode.rawValue)")
                            .accessibilityAction(named: "Move left") { move(mode, offset: -1) }
                            .accessibilityAction(named: "Move right") { move(mode, offset: 1) }
                    }
                }
                .padding(.leading, 10)
                .frame(height: 44)
                .background(dragging == mode ? NavigationStyle.accent.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .offset(y: dragging == mode ? dragOffset : 0)
                .zIndex(dragging == mode ? 1 : 0)
                .shadow(color: dragging == mode ? .black.opacity(0.35) : .clear, radius: 8, y: 4)
                .transaction { if dragging == mode { $0.animation = nil } }
                .contentShape(Rectangle())

            }
            if !configuration.hidden.isEmpty {
                MenuSection("Available")
                ForEach(configuration.order.filter { configuration.hidden.contains($0) }) { mode in
                    Button { toggle(mode) } label: {
                        HStack(spacing: 8) {
                            modeLabel(mode)
                            Spacer()
                            PhosphorIcon("Plus", size: 20).foregroundStyle(NavigationStyle.accent)
                                .frame(width: 44, height: 44)
                        }.padding(.leading, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(mode.title)")
                    .accessibilityIdentifier("modes.visible.\(mode.rawValue)")
                }
            }
        }
        .frame(width: 280)
        .onDisappear { dragging = nil }
    }

    private func modeLabel(_ mode: ContentMode) -> some View {
        HStack(spacing: 10) {
            PhosphorIcon(mode.symbol, size: 20).frame(width: 28, height: 36)
                .foregroundStyle(.secondary)
            Text(mode.title).font(.body).foregroundStyle(.primary)
        }
    }

    private func toggle(_ mode: ContentMode) {
        var next = configuration
        next.toggle(mode)
        withAnimation(motion) { savedModes = next.storage }
    }

    private func move(_ mode: ContentMode, offset: Int) {
        var next = configuration
        let visible = next.visible
        guard let index = visible.firstIndex(of: mode), visible.indices.contains(index + offset) else { return }
        next.move(mode, to: visible[index + offset])
        savedModes = next.storage
    }
    private func drag(_ mode: ContentMode, translation: CGFloat) {
        var next = configuration
        let visible = next.visible
        guard mode != .all, let index = visible.firstIndex(of: mode) else { return }
        if dragging == nil { dragging = mode; dragStartIndex = index }
        let destination = min(visible.count - 1, max(1, dragStartIndex + Int((translation / 48).rounded())))
        if destination != index {
            next.move(mode, to: visible[destination])
            withAnimation(motion) { savedModes = next.storage }
        }
        dragOffset = translation - CGFloat(destination - dragStartIndex) * 48
    }

}

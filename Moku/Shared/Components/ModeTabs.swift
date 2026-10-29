import SwiftUI

/// Shared, centered media tabs for page headers and filters.
struct ModeTabs: View {
    @Binding var mode: ContentMode
    var prefix = "recent"
    var onSelect: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("preferences.animations") private var animations = true
    @AppStorage("preferences.modeTabs") private var savedModes = ""
    private var configuration: ModeTabConfiguration { ModeTabConfiguration(storage: savedModes) }
    private let preferredTabWidth: CGFloat = 88
    private var reduceMotion: Bool { systemReduceMotion || !animations }

    var body: some View {
        GeometryReader { geometry in
            let modes = configuration.visible
            let tabWidth = min(preferredTabWidth, geometry.size.width / CGFloat(modes.count))
            let leadingInset = (geometry.size.width - tabWidth * CGFloat(modes.count)) / 2
            let selectedIndex = modes.firstIndex(of: mode) ?? 0

            HStack(spacing: 0) {
                ForEach(modes) { choice in
                    Button {
                        mode = choice
                        onSelect()
                    } label: {
                        Text(choice.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(mode == choice ? 0.92 : 0.45))
                            .lineLimit(1)
                            .frame(width: tabWidth, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ModeTabButtonStyle())
                    .accessibilityIdentifier("\(prefix).mode.\(choice.rawValue)")
                    .accessibilityAddTraits(mode == choice ? .isSelected : [])
                    .overlay {
                        if choice == .all {
                            Text(choice.title).font(.subheadline.weight(.medium))
                                .hidden().allowsHitTesting(false).accessibilityHidden(true)
                                .overlay(alignment: .trailing) {
                                    OverflowMenu(dismissOnSelection: false, dismissOnAnchorChange: false) {
                                        ModeTabsMenu()
                                    } label: {
                                        PhosphorIcon("CaretDown", size: 10)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 28, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel("Customize visible modes")
                                    .accessibilityIdentifier("\(prefix).mode.customize")
                                    .offset(x: 28)
                                }
                        }
                    }
                }

            }
            .frame(maxWidth: .infinity, alignment: .center)
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(.white.opacity(0.14)).frame(height: 0.5)
                    Capsule().fill(NavigationStyle.accent)
                        .frame(width: max(0, tabWidth - 12), height: 2)
                        .offset(x: leadingInset + CGFloat(selectedIndex) * tabWidth + 6)
                        .animation(reduceMotion ? nil : NavigationStyle.selectionAnimation, value: mode)
                }
                .frame(height: 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(height: 44)
        .onChange(of: configuration.visible, initial: true) { _, visible in
            if !visible.contains(mode) { mode = .all; onSelect() }
        }
        .onChange(of: mode) { _, selected in
            if !configuration.visible.contains(selected) { mode = .all; onSelect() }
        }
    }
}

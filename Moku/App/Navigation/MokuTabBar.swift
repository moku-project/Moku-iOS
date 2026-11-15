import SwiftUI

/// Hides the tab bar while a page needs the bottom edge, such as Library's selection bar.
@MainActor @Observable final class TabBarState {
    static let shared = TabBarState()
    var hidden = false
}

/// Android's bottom bar on iOS: the tabs in one glass capsule, with the content
/// switcher as its own glass button beside it. Tapping the switcher steps to the
/// next content type; holding it lists them all.
struct MokuTabBar: View {
    @Binding var selection: AppTab
    let reselect: (AppTab) -> Void
    @AppStorage("contentMode") private var mode: ContentMode = .all
    @AppStorage("preferences.modeTabs") private var savedModes = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    static let height: CGFloat = 60

    var body: some View {
        GlassGroup {
            HStack(spacing: 10) {
                tabs
                modeButton
            }
        }
        .padding(.horizontal, 16)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let selected = tab == selection
                Button {
                    if selected { reselect(tab) } else { selection = tab }
                } label: {
                    Image(systemName: selected ? tab.selectedSystemImage : tab.systemImage)
                        .font(.system(size: 20, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? NavigationStyle.accent : .secondary)
                        .frame(maxWidth: .infinity, minHeight: Self.height - 10)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(NavigationStyle.accent.opacity(0.18))
                                    .matchedGeometryEffect(id: "selection", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .padding(5)
        .frame(height: Self.height)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8), value: selection)
        .glassSurface(Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var modes: [ContentMode] { ModeTabConfiguration(storage: savedModes).visible }

    private var modeButton: some View {
        Menu {
            Picker("Content", selection: $mode) {
                ForEach(modes) { choice in
                    Label(choice.title, systemImage: choice.systemImage).tag(choice)
                        .accessibilityIdentifier("mode.\(choice.rawValue)")
                }
            }
        } label: {
            Image(systemName: mode.systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(NavigationStyle.accent)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.height, height: Self.height)
                .contentShape(Circle())
        } primaryAction: {
            let all = modes
            guard !all.isEmpty else { return }
            let next = ((all.firstIndex(of: mode) ?? -1) + 1) % all.count
            mode = all[next]
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .glassSurface(Circle())
        .sensoryFeedback(.selection, trigger: mode)
        .accessibilityLabel("Content type")
        .accessibilityValue(mode.title)
        .accessibilityHint("Tap for the next type. Hold to choose one.")
        .accessibilityIdentifier("mode.button")
    }
}

extension ContentMode {
    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .manga: "photo"
        case .novels: "book"
        case .anime: "film"
        }
    }
}

/// Merges neighbouring glass shapes where Liquid Glass is available.
private struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) { content }
        } else {
            content
        }
    }
}

extension View {
    /// Liquid Glass on iOS 26 and later, a blurred material before that.
    @ViewBuilder func glassSurface<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.08), lineWidth: 0.5))
        }
    }
}

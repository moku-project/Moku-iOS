import SwiftUI

struct NavigationBar: View {
    @AppStorage("preferences.modeTabs") private var savedModes = ""
    @Binding var selection: AppTab
    @Binding var mode: ContentMode
    @Binding var isModePickerPresented: Bool
    var isCompact = false
    @State private var libraryHoldHandled = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("preferences.animations") private var animations = true
    private var reduceMotion: Bool { systemReduceMotion || !animations }

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View { chrome.dynamicTypeSize(...DynamicTypeSize.xxLarge) }
    // Navigation chrome stops growing at the largest standard size; content keeps scaling.
    @ViewBuilder private var chrome: some View {
        VStack(spacing: 8) {
            if isModePickerPresented {
                HStack(spacing: 4) {
                    ForEach(ModeTabConfiguration(storage: savedModes).visible) { item in
                        Button {
                            mode = item
                            select(.library)
                        } label: {
                            PhosphorIcon(
                                item.symbol, size: 18, weight: mode == item ? "fill" : "light"
                            )
                            .foregroundStyle(
                                mode == item ? NavigationStyle.accent : .secondary
                            )
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .background {
                                if mode == item {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(NavigationStyle.accent.opacity(0.12))
                                        .padding(4)
                                }
                            }
                        }
                        .accessibilityLabel(item.title)
                        .accessibilityAddTraits(mode == item ? .isSelected : [])
                        .accessibilityIdentifier("mode.\(item.rawValue)")
                    }
                }
                .padding(.horizontal, 6)
                .modifier(FloatingSurface(cornerRadius: 12))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Content modes")
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.88, anchor: .bottom))
                                .combined(with: .offset(y: 10)),
                            removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .bottom))
                                .combined(with: .offset(y: 6))
                        )
                )
            }

            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    Group {
                        if tab == .library {
                            Button {
                                // A recognized hold opens the picker; its release is not a tap.
                                if libraryHoldHandled { libraryHoldHandled = false }
                                else { select(.library) }
                            } label: {
                                tabIcon(tab)
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.3)
                                    .onEnded { _ in
                                        libraryHoldHandled = true
                                        showModePicker()
                                    }
                            )
                            .accessibilityValue(mode.title)
                            .accessibilityHint("Hold to choose All, Manga, Novels, or Anime")
                            .accessibilityAction(named: "Choose content mode") {
                                showModePicker()
                            }
                        } else {
                            Button {
                                select(tab)
                            } label: {
                                tabIcon(tab)
                            }
                        }
                    }
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                    .accessibilityIdentifier("tab.\(tab.rawValue)")
                }
            }
            .background {
                GeometryReader { geometry in
                    let slot = geometry.size.width / CGFloat(AppTab.allCases.count)
                    let index = AppTab.allCases.firstIndex(of: selection) ?? 0
                    // Keep a four-point inset from the shell, including at either end.
                    let width = slot + 2 * (NavigationStyle.navigationHorizontalPadding - 4)
                    let height = geometry.size.height - 8
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(NavigationStyle.accent.opacity(0.16))
                        .overlay {
                            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                                .strokeBorder(NavigationStyle.accent.opacity(0.18), lineWidth: 0.5)
                        }
                        .frame(width: width, height: height)
                        .offset(
                            x: slot * CGFloat(index) + (slot - width) / 2,
                            y: (geometry.size.height - height) / 2
                        )
                        .animation(
                            reduceMotion ? nil : NavigationStyle.selectionAnimation,
                            value: selection
                        )
                        // Page selection disables animations for immediate navigation.
                        // Re-enable them only on the moving selection highlight.
                        .transaction { $0.disablesAnimations = reduceMotion }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, NavigationStyle.navigationHorizontalPadding)
            .modifier(
                FloatingSurface(
                    cornerRadius: isCompact
                        ? NavigationStyle.compactNavigationHeight / 2
                        : NavigationStyle.navigationCornerRadius, tintOpacity: 0.12)
            )
            .frame(maxWidth: isCompact ? 300 : 336)
            .accessibilityElement(children: .contain)
            .accessibilityValue(isCompact ? "Compact" : "Expanded")
            .accessibilityIdentifier("navigation.island")
            .accessibilityLabel("Main navigation")
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86),
            value: isCompact
        )
        .onChange(of: isModePickerPresented) { _, presented in
            if !presented { libraryHoldHandled = false }
        }
        .buttonStyle(NavigationPressStyle())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: isModePickerPresented)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: mode)
        .padding(.horizontal, 16)
        .padding(.top, NavigationStyle.navigationSpacing)
        .padding(.bottom, NavigationStyle.navigationBottomPadding)
        .frame(maxWidth: .infinity)
    }

    private func showModePicker() {
        isModePickerPresented = true
    }

    private func select(_ tab: AppTab) {
        selection = tab
        isModePickerPresented = false
    }

    private func tabIcon(_ tab: AppTab) -> some View {
        PhosphorIcon(
            tab.symbol, size: isCompact ? 24 : 27,
            weight: selection == tab
                ? (tab == .browse || tab == .downloads ? "bold" : "fill") : "light"
        )
        .foregroundStyle(GeneralStyle.text)
        .frame(width: 44, height: 44)
        .frame(maxWidth: .infinity)
        .frame(
            height: isCompact
                ? NavigationStyle.compactNavigationHeight : NavigationStyle.navigationHeight
        )
        .contentShape(Rectangle())
    }

}

private struct NavigationPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("preferences.animations") private var animations = true
    private var reduceMotion: Bool { systemReduceMotion || !animations }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.88)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

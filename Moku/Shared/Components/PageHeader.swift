import SwiftUI

/// Equal side columns keep every page title centered.
struct PageHeader: View {
    @AppStorage("preferences.modeTabs") private var savedModes = ""
    let title: String
    var showsDivider = false
    var modeSymbol: String? = nil
    var modeLabel: String? = nil
    var isModePresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("preferences.animations") private var animations = true
    var selectMode: ((ContentMode) -> Void)? = nil
    var onMode: (() -> Void)? = nil
    @Environment(\.openMokuLinks) private var openMokuLinks
    @Environment(\.openSettings) private var openSettings

    @ScaledMetric(relativeTo: .body) private var titleSize = 18.7
    @State private var headerWidth: CGFloat = 390

    // Pass unscaled artwork sizes; PhosphorIcon applies Dynamic Type once.
    private var headerIconSize: CGFloat { headerWidth >= 400 ? 24 : 20.4 }

    var body: some View { chrome0.dynamicTypeSize(...DynamicTypeSize.xxLarge) }
    // Navigation chrome stops growing at the largest standard size; content keeps scaling.
    @ViewBuilder private var chrome0: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button(action: openMokuLinks) {
                    Image("MokuMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .foregroundStyle(NavigationStyle.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Moku links")
                .accessibilityHint("Opens the project and community links")
                .accessibilityIdentifier("header.mokuLinks")

                Text(title).accessibilityIdentifier("header.title")
                    .font(.system(size: titleSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)

                Button(action: openSettings) {
                    PhosphorIcon("GearSix", size: headerIconSize, weight: "light")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityLabel("Settings")
                .pillBackdrop(isModePresented)
                .accessibilityIdentifier("header.settings")
            }
            .frame(minHeight: 52)
            .padding(.horizontal, NavigationStyle.pagePadding)
            if let onMode, let modeSymbol {
                IconRail(
                    title: modeLabel ?? title,
                    symbol: modeSymbol, isPresented: isModePresented,
                    itemCount: ModeTabConfiguration(storage: savedModes).visible.filter { $0.title != modeLabel }.count,
                    reduceMotion: reduceMotion || !animations,
                    labelFont: .subheadline.weight(.medium),
                    iconSize: 18, iconColor: NavigationStyle.accent,
                    instantTitleChange: true,
                    toggle: onMode
                ) {
                    ForEach(ModeTabConfiguration(storage: savedModes).visible.filter { $0.title != modeLabel }) { choice in
                        IconRailRow(title: choice.title, symbol: choice.symbol, selected: false) {
                            selectMode?(choice)
                        }
                        .accessibilityIdentifier("library.mode.\(choice.rawValue)")
                    }
                }
                .accessibilityAction(.escape) { if isModePresented { onMode() } }
                .accessibilityLabel("Library mode: \(modeLabel ?? title)")
                .accessibilityIdentifier("library.currentMode")
                .accessibilityValue(isModePresented ? "Expanded" : "Collapsed")
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            headerWidth = $0
        }
        .overlay(alignment: .bottom) { if showsDivider { HeaderDivider() } }
    }
}

struct HeaderDivider: View {
    var body: some View { chrome1.dynamicTypeSize(...DynamicTypeSize.xxLarge) }
    // Navigation chrome stops growing at the largest standard size; content keeps scaling.
    @ViewBuilder private var chrome1: some View {
        Rectangle().fill(GeneralStyle.border).frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

/// Navigation pages keep their title centered without exposing global shortcuts.
struct BackHeader: View {
    let title: String
    let backLabel: String
    var identifier = "settings.back"
    let back: () -> Void
    @ScaledMetric(relativeTo: .body) private var titleSize = 18.7
    @State private var headerWidth: CGFloat = 390

    var body: some View { chrome2.dynamicTypeSize(...DynamicTypeSize.xxLarge) }
    // Navigation chrome stops growing at the largest standard size; content keeps scaling.
    @ViewBuilder private var chrome2: some View {
        HStack(spacing: 4) {
            Button(action: back) {
                PhosphorIcon("CaretLeft").iconSize(headerWidth >= 400 ? 17 : 14.5)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(backLabel)
            .accessibilityIdentifier(identifier)
            Text(title).font(.system(size: titleSize, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
        }
        .padding(.horizontal, NavigationStyle.pagePadding).frame(minHeight: 52)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            headerWidth = $0
        }
        .background(NavigationStyle.background)
    }
}

#if DEBUG
    #Preview("Headers") {
        VStack(spacing: 24) {
            PageHeader(title: "More")
            PageHeader(title: "Library", modeSymbol: "Books", modeLabel: "All", onMode: {})
            BackHeader(title: "Settings", backLabel: "Back", back: {})
            Spacer()
        }
        .background(NavigationStyle.background)
        .preferredColorScheme(.dark)
    }
#endif

import SwiftUI

struct SettingsView: View {
    let backLabel: String
    let back: () -> Void
    @ScaledMetric(relativeTo: .body) private var rowTextSize = 17.5
    let openExtensions: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(SettingsCategory.visible, id: \.self) { section in
                    NavigationLink(value: section) {
                        HStack(spacing: 8) {
                            PhosphorIcon(section.symbol, size: 21.25)
                                .foregroundStyle(.secondary).frame(minWidth: 30)
                            Text(section.rawValue).font(.system(size: rowTextSize))
                            Spacer(minLength: 12)
                            PhosphorIcon("CaretRight").iconSize(13.75)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 64).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.category.\(section.rawValue)")
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .tracksNavigationScroll()
        .accessibilityIdentifier("settings.index")
        .safeAreaInset(edge: .top, spacing: 0) {
            BackHeader(
                title: "Settings", backLabel: backLabel, identifier: "account.back", back: back)
        }
        .navigationDestination(for: SettingsCategory.self) { category in
            if category == .tracking {
                TrackingSettingsDestination()
            } else {
                SettingsSectionView(category: category, openExtensions: openExtensions)
            }
        }
    }
}

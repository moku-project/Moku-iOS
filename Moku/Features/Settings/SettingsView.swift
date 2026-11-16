import SwiftUI

/// The Settings tab: sources and activity first, then preferences, as on Android.
struct SettingsView: View {
    private static let preferences: [SettingsCategory] = [
        .general, .appearance, .reader, .player, .library, .folders, .content, .automation,
        .performance, .keybinds,
    ]
    private static let data: [SettingsCategory] = [.sync, .storage, .server, .auth]

    var body: some View {
        List {
            Section {
                ForEach([MoreDestination.extensions, .tracking, .recent]) { destination in
                    NavigationLink(value: Route.more(destination)) {
                        SettingsRowLabel(
                            title: destination.rawValue, symbol: destination.tile.symbol,
                            color: destination.tile.color)
                    }
                    .accessibilityIdentifier("more.category.\(destination.rawValue)")
                }
            }
            Section("Preferences") { rows(Self.preferences) }
            Section("Data") {
                rows(Self.data)
                NavigationLink(value: Route.settings(.tracking)) {
                    SettingsRowLabel(
                        title: "Tracker Accounts", symbol: SettingsCategory.tracking.tile.symbol,
                        color: SettingsCategory.tracking.tile.color)
                }
                .accessibilityIdentifier("settings.category.Tracking")
            }
            Section {
                NavigationLink(value: Route.more(.about)) {
                    SettingsRowLabel(
                        title: "About Moku", symbol: MoreDestination.about.tile.symbol,
                        color: MoreDestination.about.tile.color)
                }
                .accessibilityIdentifier("more.category.About")
                #if DEBUG
                    rows([.devTools])
                #endif
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .accessibilityIdentifier("settings.index")
    }

    private func rows(_ categories: [SettingsCategory]) -> some View {
        ForEach(categories, id: \.self) { category in
            NavigationLink(value: Route.settings(category)) {
                SettingsRowLabel(
                    title: category.rawValue, symbol: category.tile.symbol,
                    color: category.tile.color)
            }
            .accessibilityIdentifier("settings.category.\(category.rawValue)")
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack { SettingsView() }.preferredColorScheme(.dark)
    }
#endif

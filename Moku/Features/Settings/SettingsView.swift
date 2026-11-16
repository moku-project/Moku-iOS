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
                        Label(destination.rawValue, systemImage: destination.systemImage)
                    }
                    .accessibilityIdentifier("more.category.\(destination.rawValue)")
                }
            }
            Section("Preferences") { rows(Self.preferences) }
            Section("Data") {
                rows(Self.data)
                NavigationLink(value: Route.settings(.tracking)) {
                    Label("Tracker Accounts", systemImage: "person.crop.circle.badge.checkmark")
                }
                .accessibilityIdentifier("settings.category.Tracking")
            }
            Section {
                NavigationLink(value: Route.more(.about)) {
                    Label("About Moku", systemImage: MoreDestination.about.systemImage)
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
                Label(category.rawValue, systemImage: category.systemImage)
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

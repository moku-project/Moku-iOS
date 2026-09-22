import SwiftUI

#if DEBUG
    private struct GeneralSettingsPreviewHost: View {
        @State private var home = HomeStore(fileURL: nil)
        private let defaults = UserDefaults(suiteName: "Moku.Previews.Settings")!

        var body: some View {
            NavigationStack {
                SettingsSectionView(category: .general, openExtensions: {})
            }
            .environment(home)
            .environment(ReaderPreferences(defaults: defaults))
            .defaultAppStorage(defaults)
            .tint(NavigationStyle.accent)
            .preferredColorScheme(.dark)
        }
    }

    #Preview("General Settings") {
        GeneralSettingsPreviewHost()
    }

    #Preview("General Settings · large text") {
        GeneralSettingsPreviewHost()
            .environment(\.dynamicTypeSize, .accessibility3)
    }
#endif

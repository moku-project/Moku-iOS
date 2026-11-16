import SwiftUI

#if DEBUG
    private struct HomePreviewHost: View {
        @State private var store: ReadingHistory

        init(empty: Bool = false) {
            _store = State(initialValue: HomePreviewData.makeStore(titleCount: empty ? 0 : 3))
        }

        var body: some View {
            NavigationStack {
                HomeView(store: store)
                    .background(NavigationStyle.background)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .environment(store)
            .environment(\.skeletonStorageScope, "home-preview")
            .defaultAppStorage(UserDefaults(suiteName: "Moku.Previews.Home")!)
            .preferredColorScheme(.dark)
        }
    }

    #Preview("Home · resume and activity") {
        HomePreviewHost()
    }

    #Preview("Home · large text") {
        HomePreviewHost()
            .environment(\.dynamicTypeSize, .accessibility3)
    }

    #Preview("Home · empty") {
        HomePreviewHost(empty: true)
    }
#endif

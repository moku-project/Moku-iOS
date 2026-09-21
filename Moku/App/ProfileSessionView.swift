import SwiftUI

struct ProfileSessionView: View {
    let preferences: UserDefaults
    let searchHistory: SearchHistoryStore
    @State private var home: HomeStore
    @State private var library: ProfileLibrary
    @State private var readerPreferences: ReaderPreferences

    init(profiles: ProfileStore, profileID: UUID) {
        preferences = profiles.preferences(for: profileID)
        searchHistory = SearchHistoryStore(
            url: profiles.directory(for: profileID).appending(path: "search-history.sqlite"))
        _readerPreferences = State(
            initialValue: ReaderPreferences(defaults: profiles.preferences(for: profileID)))
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: {
                $0.hasPrefix("--ui-testing-home-")
            }) {
                _home = State(initialValue: AppDependencies.homeStore)
            } else {
                _home = State(initialValue: HomeStore(fileURL: profiles.homeURL(for: profileID)))
            }
        #else
            _home = State(initialValue: HomeStore(fileURL: profiles.homeURL(for: profileID)))
        #endif
        _library = State(
            initialValue: ProfileLibrary(directory: profiles.directory(for: profileID)))
    }

    var body: some View {
        RootView(homeStore: home)
            .modifier(GeneralInterfaceBehavior())
            .environment(\.searchHistoryStore, searchHistory)
            .environment(\.skeletonProfileScope, searchHistory.url.path)
            .environment(home).environment(library).environment(readerPreferences)
            .defaultAppStorage(preferences)
            .task { await library.load() }
    }
}

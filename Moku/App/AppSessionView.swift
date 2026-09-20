import SwiftUI

struct AppSessionView: View {
    let preferences: UserDefaults
    let searchHistory: SearchHistoryStore
    @State private var home: HomeStore
    @State private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var appLock: AppLockStore
    @State private var readerPreferences: ReaderPreferences

    init(storage: AppDataStore) {
        preferences = storage.preferences
        _appLock = State(initialValue: AppLockStore(defaults: storage.preferences, scope: storage.directory.path))
        searchHistory = SearchHistoryStore(
            url: storage.directory.appending(path: "search-history.sqlite"))
        _readerPreferences = State(
            initialValue: ReaderPreferences(defaults: storage.preferences))
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: {
                $0.hasPrefix("--ui-testing-home-")
            }) {
                _home = State(initialValue: AppDependencies.homeStore)
            } else {
                _home = State(initialValue: HomeStore(fileURL: storage.homeURL))
            }
        #else
            _home = State(initialValue: HomeStore(fileURL: storage.homeURL))
        #endif
        _library = State(
            initialValue: LibraryStore(directory: storage.directory, synchronizeWithServer: !PreviewMode.isEnabled))
    }

    var body: some View {
        RootView(homeStore: home)
            .modifier(GeneralInterfaceBehavior())
            .environment(\.searchHistoryStore, searchHistory)
            .environment(\.skeletonStorageScope, searchHistory.url.path)
            .environment(home).environment(library).environment(readerPreferences).environment(appLock)
            .defaultAppStorage(preferences)
            .task { appLock.showIfLocked(); await library.load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { appLock.lock() }
                if phase == .active { appLock.showIfLocked() }
            }
    }
}

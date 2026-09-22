#if DEBUG
    import SwiftUI

    /// Disposable fixture storage, never the app's saved library or preferences.
    struct AppPreviewHost: View {
        @State private var home = HomePreviewData.makeStore()
        @State private var library: LibraryStore
        private let storage: AppDataStore
        private let history: SearchHistoryStore
        private let reader: ReaderPreferences

        init() {
            let storage = AppDataStore(
                root: URL.temporaryDirectory.appending(path: "MokuPreviews/\(UUID().uuidString)"),
                defaultsPrefix: "Moku.Previews")
            self.storage = storage
            history = SearchHistoryStore(
                url: storage.directory.appending(path: "search-history.sqlite"))
            reader = ReaderPreferences(defaults: storage.preferences)
            _library = State(initialValue: LibraryStore(directory: storage.directory))
        }

        var body: some View {
            RootView(homeStore: home)
                .environment(home)
                .environment(library)
                .environment(storage)
                .environment(reader)
                .environment(\.searchHistoryStore, history)
                .environment(\.skeletonStorageScope, "preview")
                .defaultAppStorage(storage.preferences)
                .preferredColorScheme(.dark)
                .task {
                    for entry in RecentPreviewData.entries {
                        await library.setSaved(true, entry: entry)
                    }
                }
        }
    }
#endif

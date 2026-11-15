import SwiftUI

struct AppSessionView: View {
    let preferences: UserDefaults
    let searchHistory: SearchHistoryStore
    @State private var home: HomeStore
    @State private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var appLock: AppLockStore
    @State private var readerPreferences: ReaderPreferences
    @State private var crashes = CrashReports.shared
    @State private var reportingCrash = false

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

    /// Paired desktops sync on open; the short delay keeps launch responsive.
    private func syncWithDesktop() {
        guard preferences.object(forKey: "sync.automatic") as? Bool ?? true, !PreviewMode.isEnabled else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            await DesktopSync.shared.syncIfDue(library: library)
        }
    }

    /// APP_OPEN makes the core honour the shared "Update library on app open" setting, its cooldown and paused series.
    private func updateLibraryOnOpen() {
        guard !PreviewMode.isEnabled else { return }
        Task {
            try? await Task.sleep(for: .seconds(5))
            let _: IgnoredGraphQLResult? = try? await BackendAPI.shared.graphql(
                "mutation { startLibraryUpdate(trigger: APP_OPEN) }")
        }
    }

    var body: some View {
        Group {
            if appLock.loaded {
                RootView(homeStore: home)
            } else {
                ContentSkeleton(style: .startup)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NavigationStyle.background)
            }
        }
            .modifier(GeneralInterfaceBehavior())
            .environment(\.searchHistoryStore, searchHistory)
            .environment(\.skeletonStorageScope, searchHistory.url.path)
            .environment(home).environment(library).environment(readerPreferences).environment(appLock)
            .defaultAppStorage(preferences)
            .task {
                await appLock.load()
                appLock.showIfLocked()
                await library.load()
                syncWithDesktop()
                updateLibraryOnOpen()
            }
            .alert("Moku Closed Unexpectedly", isPresented: Binding(
                get: { crashes.pending && appLock.loaded }, set: { if !$0 { crashes.pending = false } })
            ) {
                Button("Report a Problem") { reportingCrash = true }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Moku quit unexpectedly last time. A bug report helps fix it.")
            }
            .sheet(isPresented: $reportingCrash) { BugReportSheet() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                Task { await BackendAPI.shared.trimMemory() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .contentVisibilityDidChange)) { _ in
                library.invalidateServerVisibility()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    BackgroundWork.didEnterBackground(defaults: preferences)
                    appLock.lock()
                    Task { await readerPreferences.flush(); await home.flush() }
                }
                if phase == .active {
                    appLock.showIfLocked()
                    syncWithDesktop()
                }
            }
    }
}

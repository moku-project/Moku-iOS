import SwiftUI

struct AppSessionView: View {
    let preferences: UserDefaults
    let searchHistory: SearchHistoryStore
    @State private var home: ReadingHistory
    @State private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var appLock: AppLockStore
    @State private var readerPreferences: ReaderPreferences
    @State private var crashes = CrashReports.shared
    @State private var reportingCrash = false

    init(storage: AppDataStore) {
        preferences = storage.preferences
        _appLock = State(
            initialValue: AppLockStore(defaults: storage.preferences, scope: storage.directory.path)
        )
        searchHistory = SearchHistoryStore(
            url: storage.directory.appending(path: "search-history.sqlite"))
        _readerPreferences = State(
            initialValue: ReaderPreferences(defaults: storage.preferences))
        _home = State(initialValue: AppDependencies.readingHistory(legacyURL: storage.homeURL))
        _library = State(
            initialValue: LibraryStore(
                directory: storage.directory, synchronizeWithServer: !PreviewMode.isEnabled))
    }

    /// Paired devices sync on open; the short delay keeps launch responsive.
    private func refreshSync() {
        guard !PreviewMode.isEnabled else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            await Backend.shared.refreshSync()
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
                RootView(history: home)
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
        .task { await home.load() }
        .defaultAppStorage(preferences)
        .task {
            await appLock.load()
            appLock.showIfLocked()
            await library.load()
            refreshSync()
            updateLibraryOnOpen()
        }
        .alert(
            "Moku Closed Unexpectedly",
            isPresented: Binding(
                get: { crashes.pending && appLock.loaded },
                set: { if !$0 { crashes.pending = false } })
        ) {
            Button("Report a Problem") { reportingCrash = true }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Moku quit unexpectedly last time. A bug report helps fix it.")
        }
        .sheet(isPresented: $reportingCrash) { BugReportSheet() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification)
        ) { _ in
            Task { await BackendAPI.shared.trimMemory() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .contentVisibilityDidChange)) { _ in
            library.invalidateServerVisibility()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundWork.didEnterBackground(defaults: preferences)
                appLock.lock()
                Task { await readerPreferences.flush() }
            }
            if phase == .active {
                Task {
                    await Backend.shared.recoverIfNeeded()
                    await Backend.shared.refreshSync()
                    await home.refresh()
                }
                appLock.showIfLocked()
            }
        }
    }
}

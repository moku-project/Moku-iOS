import SwiftUI

/// A page pushed onto a tab's navigation stack.
enum Route: Hashable {
    case details(DetailRoute)
    case more(MoreDestination)
    case settings(SettingsCategory)
    case source(SourceRoute)
}

/// Opens a title, optionally at a chapter. Identity is the title and chapter.
struct DetailRoute: Hashable {
    let entry: MediaEntry
    var chapterID: String?
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entry.id == rhs.entry.id && lhs.chapterID == rhs.chapterID
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(entry.id)
        hasher.combine(chapterID)
    }
}

/// Browses one installed source.
struct SourceRoute: Hashable {
    let source: SourceExtension
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.source.id == rhs.source.id }
    func hash(into hasher: inout Hasher) { hasher.combine(source.id) }
}

struct RootView: View {
    @State private var navigation: RootNavigation = {
        // Desktop "Default view". Read once at launch; changing it applies next time.
        let navigation = RootNavigation()
        let stored = AppDataStore.shared.preferences.string(forKey: "preferences.startTab")
        if let tab = stored.flatMap(AppTab.init(rawValue:)), AppTab.startChoices.contains(tab) {
            navigation.selection = tab
        }
        return navigation
    }()
    let homeStore: HomeStore
    @State private var downloadsModel = DownloadsViewModel.makeDefault()
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("preferences.systemTheme") private var systemTheme = false
    @AppStorage("preferences.darkTheme") private var darkTheme = "midnight"
    @AppStorage("preferences.lightTheme") private var lightTheme = "light"
    @AppStorage("preferences.customThemes") private var customThemes = Data()
    @AppStorage("preferences.theme") private var theme = "midnight"
    private var effectiveTheme: String { systemTheme ? (colorScheme == .dark ? darkTheme : lightTheme) : theme }
    private var palette: NativeTheme { NativeTheme.resolve(effectiveTheme, custom: customThemes) }

    @AppStorage("onboarding.completed") private var onboarded = false
    @AppStorage("whatsNew.seenVersion") private var seenVersion = ""
    /// UI tests and previews start inside the app, not on the welcome screen.
    private static let skipsOnboarding: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-onboarding") { return false }
        return PreviewMode.isEnabled || arguments.contains { $0.hasPrefix("--ui-testing") || $0 == "--acceptance" }
    }()

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { navigation.selection },
            set: { tab in
                // Choosing the open tab again returns it to its first page.
                if tab == navigation.selection { navigation.paths[tab] = [] }
                navigation.select(tab)
            })
    }

    var body: some View {
        TabView(selection: tabSelection) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab, role: tab == .browse ? .search : nil) {
                    RootTabPage(
                        tab: tab, activity: navigation.tabs[tab], navigation: navigation,
                        homeStore: homeStore, downloadsModel: downloadsModel
                    )
                    .equatable()
                    .accessibilityIdentifier("page.\(tab.rawValue)")
                }
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .tabBarMinimizeBehaviorIfAvailable()
        .background(NavigationStyle.background.ignoresSafeArea())
        .fullScreenCover(isPresented: Binding(get: { !onboarded && !Self.skipsOnboarding }, set: { _ in })) {
            OnboardingView(
                openExtensions: { navigation.open(.more(.extensions), in: .settings) },
                openSettings: { navigation.open(.settings(.sync), in: .settings) },
                finish: {
                    onboarded = true
                    // A fresh install has nothing "new" to show after onboarding.
                    seenVersion = WhatsNew.current
                })
        }
        .sheet(isPresented: Binding(
            get: { onboarded && !Self.skipsOnboarding && seenVersion != WhatsNew.current
                && WhatsNew.releases.contains { $0.version == WhatsNew.current } },
            set: { if !$0 { seenVersion = WhatsNew.current } })
        ) {
            if let release = WhatsNew.releases.first(where: { $0.version == WhatsNew.current }) {
                WhatsNewView(release: release) { seenVersion = WhatsNew.current }
            }
        }
        .environment(\.openSettings) { navigation.select(.settings) }
        .tint(NavigationStyle.accent)
        .preferredColorScheme(systemTheme ? nil : (palette.isLight ? .light : .dark))
        .onChange(of: palette, initial: true) { _, value in
            AppTheme.shared.name = value.id
            AppTheme.shared.palette = value
        }
        .background {
            #if DEBUG
            NavigationFrameProbe(tab: navigation.selection).frame(width: 1, height: 1)
            #endif
        }
        .modifier(OverflowMenuHost())
        .modifier(MokuLinksHost())
    }
}

extension View {
    /// Lets the tab bar shrink while content scrolls, where the system supports it.
    @ViewBuilder func tabBarMinimizeBehaviorIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

/// Each page observes only its own activity. The stable reference inputs keep
/// Library data and unrelated route changes out of other tabs' view dependencies.
private struct RootTabPage: View, Equatable {
    let tab: AppTab
    let activity: TabActivity
    let navigation: RootNavigation
    let homeStore: HomeStore
    let downloadsModel: DownloadsViewModel
    @AppStorage("contentMode") private var mode: ContentMode = .all
    @AppStorage("preferences.language") private var sourceLanguage = "all"
    @Environment(LibraryStore.self) private var library

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tab == rhs.tab && lhs.activity === rhs.activity
            && lhs.navigation === rhs.navigation && lhs.homeStore === rhs.homeStore
            && lhs.downloadsModel === rhs.downloadsModel
    }

    private var path: Binding<[Route]> {
        Binding(get: { navigation.paths[tab] ?? [] }, set: { navigation.paths[tab] = $0 })
    }

    var body: some View {
        NavigationStack(path: path) {
            Group {
                if activity.hasVisited { page } else { Color.clear }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationDestination(for: Route.self) { route in
                destination(route)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NavigationStyle.background.ignoresSafeArea())
            }
        }
    }

    private func openDetails(_ entry: MediaEntry, chapterID: String? = nil) {
        navigation.open(.details(DetailRoute(entry: entry, chapterID: chapterID)), in: tab)
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .details(let detail):
            DetailsView(entry: detail.entry, initialChapterID: detail.chapterID) {
                navigation.pop(route, in: tab)
            }
        case .more(let destination):
            MoreDestinationView(
                destination: destination, mode: $mode,
                searchSource: { source in navigation.open(.source(SourceRoute(source: source)), in: tab) }
            )
            .navigationTitle(destination.rawValue)
            .navigationBarTitleDisplayMode(.inline)
        case .settings(let category):
            if category == .tracking {
                TrackingSettingsDestination()
            } else {
                SettingsSectionView(
                    category: category,
                    openExtensions: { navigation.open(.more(.extensions), in: .settings) })
            }
        case .source(let route):
            SourceBrowseView(
                source: route.source, openEntry: { openDetails($0) },
                close: { navigation.pop(.source(route), in: tab) })
            .id(route.source.packageName)
        }
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .home:
            HomeView(
                store: homeStore, isActive: activity.isActive,
                onOpenLibrary: { navigation.select(.library) },
                onGenre: { genre in
                    let model = SearchViewModel(
                        repository: AppDependencies.searchRepository,
                        language: sourceLanguage == "all" ? nil : sourceLanguage)
                    model.draft.method = .tags
                    model.draft.genres = [genre]
                    model.apply()
                    navigation.globalSearchModel = model
                    navigation.select(.browse, language: sourceLanguage)
                },
                onOpenLibraryTitle: { entry in
                    mode = entry.media
                    openDetails(entry)
                },
                onOpenTitle: { entry, chapterID in openDetails(entry, chapterID: chapterID) })
        case .downloads:
            DownloadsView(model: downloadsModel, isActive: activity.isActive)
        case .library:
            LibraryView(
                mode: $mode, isActive: activity.isActive,
                downloadedIDs: downloadsModel.completedTitleIDs,
                onBrowse: { navigation.select(.browse, language: sourceLanguage) },
                onSearch: { navigation.select(.browse, language: sourceLanguage) },
                onOpen: { openDetails($0) })
        case .browse:
            if let model = navigation.globalSearchModel {
                SearchView(
                    model: model, openEntry: { openDetails($0) }, close: {},
                    isPage: true, isActive: activity.isActive,
                    readingSnapshot: homeStore.snapshot, savedEntries: library.entries
                )
                .id(ObjectIdentifier(model))
            }
        case .settings:
            SettingsView()
        }
    }
}

@MainActor @Observable private final class RootNavigation {
    var selection: AppTab = .library { didSet { updateActivity() } }
    var paths: [AppTab: [Route]] = [:] { didSet { updateActivity() } }
    var globalSearchModel: SearchViewModel?
    let tabs = TabActivityStore()

    init() { prepareSearch(language: "all") }

    /// A tab's first page is active only while nothing is pushed over it.
    private func updateActivity() {
        tabs.update(selection: selection, covered: !(paths[selection] ?? []).isEmpty)
    }

    private func prepareSearch(language: String) {
        if globalSearchModel == nil {
            globalSearchModel = SearchViewModel(
                repository: AppDependencies.searchRepository,
                language: language == "all" ? nil : language)
        }
    }

    func select(_ tab: AppTab, language: String = "all") {
        #if DEBUG
        NavigationTiming.begin(tab)
        #endif
        if tab == .browse { prepareSearch(language: language) }
        selection = tab
    }

    func open(_ route: Route, in tab: AppTab) {
        if selection != tab { select(tab) }
        var path = paths[tab] ?? []
        if path.last != route { path.append(route) }
        paths[tab] = path
    }

    /// Pops `route` and anything above it.
    func pop(_ route: Route, in tab: AppTab) {
        guard var path = paths[tab], let index = path.lastIndex(of: route) else { return }
        path.removeSubrange(index...)
        paths[tab] = path
    }
}

#if DEBUG
    #Preview {
        AppPreviewHost()
    }
#endif

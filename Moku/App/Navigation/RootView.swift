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
        // Read once at launch; a changed default view applies next time.
        let navigation = RootNavigation()
        let stored = AppDataStore.shared.preferences.string(forKey: "preferences.startTab")
        if let tab = stored.flatMap(AppTab.init(rawValue:)) {
            navigation.selection = tab
        }
        return navigation
    }()
    let homeStore: HomeStore
    @State private var downloadsModel = DownloadsViewModel.makeDefault()
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("preferences.systemTheme") private var systemTheme = false
    @AppStorage("preferences.darkTheme") private var darkTheme = "dark"
    @AppStorage("preferences.lightTheme") private var lightTheme = "light"
    @AppStorage("preferences.customThemes") private var customThemes = Data()
    @AppStorage("preferences.theme") private var theme = "dark"
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
        Binding(get: { navigation.selection }, set: { navigation.select($0) })
    }

    @State private var keyboardVisible = false
    private var barVisible: Bool { !keyboardVisible && !TabBarState.shared.hidden }

    var body: some View {
        TabView(selection: tabSelection) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    RootTabPage(
                        tab: tab, activity: navigation.tabs[tab], navigation: navigation,
                        homeStore: homeStore, downloadsModel: downloadsModel
                    )
                    .equatable()
                    .environment(\.tabBarInset, barVisible ? MokuTabBar.height + 8 : 0)
                    .toolbar(.hidden, for: .tabBar)
                    .accessibilityIdentifier("page.\(tab.rawValue)")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if barVisible {
                MokuTabBar(
                    selection: tabSelection,
                    // Choosing the open tab again returns it to its first page.
                    reselect: { navigation.paths[$0] = [] })
                .padding(.bottom, 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: barVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
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
        .environment(\.openContentTypes) { navigation.open(.settings(.appearance), in: .settings) }
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
        .sourceVerificationHost()
    }
}

/// Observes only its own activity; stable inputs keep Library data and other routes out of each tab's dependencies.
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
            .clearsTabBar()
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationDestination(for: Route.self) { route in
                destination(route)
                    .environment(\.searchGenre, searchGenre)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clearsTabBar()
                    .background(NavigationStyle.background.ignoresSafeArea())
            }
        }
    }

    /// Opens Search filtered by one genre (Home hero chips and title pages).
    private func searchGenre(_ genre: String) {
        let model = SearchViewModel(
            repository: AppDependencies.searchRepository,
            language: sourceLanguage == "all" ? nil : sourceLanguage)
        model.draft.method = .tags
        model.draft.genres = [genre]
        model.apply()
        navigation.globalSearchModel = model
        navigation.select(.browse, language: sourceLanguage)
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
                onGenre: searchGenre,
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
                onSearch: { query in
                    navigation.select(.browse, language: sourceLanguage)
                    navigation.globalSearchModel?.query = query
                    navigation.globalSearchModel?.submit()
                },
                onOpen: { openDetails($0) })
        case .browse:
            if let model = navigation.globalSearchModel {
                SearchView(
                    model: model, openEntry: { openDetails($0) }, isActive: activity.isActive,
                    openSources: { navigation.open(.more(.extensions), in: .browse) })
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

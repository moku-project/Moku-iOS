import SwiftUI

struct RootView: View {
    @State private var pillDropdownOpen = false
    @State private var libraryPopupPresented = false
    @State private var scrollNavigation = NavigationState()
    @State private var navigation: RootNavigation = {
        // Desktop "Default view". Read once at launch; changing it applies next time.
        let navigation = RootNavigation()
        let stored = AppDataStore.shared.preferences.string(forKey: "preferences.startTab")
        if let tab = stored.flatMap(AppTab.init(rawValue:)), tab != .more { navigation.selection = tab }
        return navigation
    }()
    let homeStore: HomeStore
    @AppStorage("preferences.language") private var sourceLanguage = "all"
    @State private var downloadsModel = DownloadsViewModel.makeDefault()
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("preferences.systemTheme") private var systemTheme = false
    @AppStorage("preferences.darkTheme") private var darkTheme = "midnight"
    @AppStorage("preferences.lightTheme") private var lightTheme = "light"
    @AppStorage("preferences.customThemes") private var customThemes = Data()
    private var effectiveTheme: String { systemTheme ? (colorScheme == .dark ? darkTheme : lightTheme) : theme }
    private var palette: NativeTheme { NativeTheme.resolve(effectiveTheme, custom: customThemes) }
    @AppStorage("preferences.theme") private var theme = "midnight"
    @AppStorage("contentMode") private var mode: ContentMode = .all
    private func accountBackLabel(for page: AccountPage) -> String {
        if let index = navigation.accountPages.firstIndex(of: page), index > 0 {
            return "Back to \(navigation.accountPages[index - 1].rawValue)"
        }
        return "Back to \(pageTitle(for: navigation.selection))"
    }

    @State private var searchKeyboardVisible = false
    @AppStorage("onboarding.completed") private var onboarded = false
    @AppStorage("whatsNew.seenVersion") private var seenVersion = ""
    /// UI tests and previews start inside the app, not on the welcome screen.
    private static let skipsOnboarding: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-onboarding") { return false }
        return PreviewMode.isEnabled || arguments.contains { $0.hasPrefix("--ui-testing") || $0 == "--acceptance" }
    }()

    private var tabSelection: Binding<AppTab> {
        Binding(get: { navigation.selection }, set: { navigation.select($0, language: sourceLanguage) })
    }

    private var navigationContent: some View {
        @Bindable var navigation = navigation
        return ZStack {
            // Native tab containment detaches inactive pages from layout and rendering.
            // Keep page state, but do not composite every visited page at opacity zero.
            TabView(selection: $navigation.selection) {
                ForEach(AppTab.allCases) { tab in
                    RootTabPage(
                        tab: tab, activity: navigation.tabs[tab], navigation: navigation,
                        homeStore: homeStore, downloadsModel: downloadsModel,
                        scrollNavigation: scrollNavigation, pillDropdownOpen: pillDropdownOpen
                    )
                    .equatable()
                    .clipped()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(tab)
                }
            }
            .opacity(navigation.accountPage == nil ? 1 : 0)
            .allowsHitTesting(navigation.accountPage == nil)
            .accessibilityHidden(navigation.accountPage != nil)
            ForEach(navigation.accountPages, id: \.self) { page in
                NavigationStack {
                    Group {
                        switch page {
                        case .settings:
                            SettingsView(
                                backLabel: accountBackLabel(for: page),
                                back: { if navigation.accountPage == page { navigation.accountPages.removeLast() } },
                                openExtensions: {
                                    navigation.accountPage = nil
                                    navigation.morePath = [.extensions]
                                    navigation.selection = .more
                                })
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .environment(\.navigationScrollChanged) { old, new in
                        guard navigation.accountPage == page, !navigation.isModePickerPresented
                        else { return }
                        scrollNavigation.update(from: old, to: new)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NavigationStyle.background)
                }
                .opacity(navigation.accountPage == page ? 1 : 0)
                .allowsHitTesting(navigation.accountPage == page)
                .accessibilityHidden(navigation.accountPage != page)
            }
            if navigation.isModePickerPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { dismissNavigationPopups() }
                    .accessibilityLabel("Dismiss content modes")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { dismissNavigationPopups() }
                    .accessibilityIdentifier("modePicker.dismiss")
            }
        }
    }

    private var isNavigationCompact: Bool {
        scrollNavigation.isCompact && !navigation.isModePickerPresented
    }

    private var bottomNavigation: some View {
        @Bindable var navigation = navigation
        // Transparent overlay: content continues behind the island. Scroll
        // content and indicator margins are configured independently below.
        return Color.clear.frame(height: NavigationStyle.navigationInset)
            .frame(maxWidth: .infinity)

            .overlay(alignment: .bottom) {
                NavigationBar(
                    selection: tabSelection,
                    mode: $mode,
                    isModePickerPresented: $navigation.isModePickerPresented,
                    isCompact: isNavigationCompact
                )
                .opacity(
                    !libraryPopupPresented
                        && !(navigation.selection == .browse && searchKeyboardVisible) ? 1 : 0
                )
                .allowsHitTesting(
                    !libraryPopupPresented && !(navigation.selection == .browse && searchKeyboardVisible)
                )
                .accessibilityHidden(
                    libraryPopupPresented || (navigation.selection == .browse && searchKeyboardVisible))
            }
    }

    private func pageTitle(for tab: AppTab) -> String {
        switch tab {
        case .more: navigation.morePath.last?.rawValue ?? "More"
        case .library: "Library"
        default: tab.title
        }
    }

    private func dismissNavigationPopups() {
        navigation.isModePickerPresented = false
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let bottomGap = max(
                    0, geometry.safeAreaInsets.bottom - NavigationStyle.navigationLowering)
                // Scroll indicators already include the system bottom safe area.
                // Add only the distance from that edge to the visible island top.
                let indicatorBottomInset = max(
                    0,
                    (isNavigationCompact
                        ? NavigationStyle.compactNavigationHeight
                        : NavigationStyle.navigationHeight)
                        + NavigationStyle.navigationBottomPadding
                        + NavigationStyle.navigationIndicatorSpacing + bottomGap
                        - geometry.safeAreaInsets.bottom)
                ZStack(alignment: .bottom) {
                    navigationContent
                        .environment(
                            \.navigationContentBottomInset,
                            NavigationStyle.navigationInset + bottomGap
                        )
                        .environment(
                            \.navigationContentSafeAreaAdjustment, geometry.safeAreaInsets.bottom
                        )
                        .environment(
                            \.navigationIndicatorBottomInset,
                            indicatorBottomInset)
                    bottomNavigation
                        .pillBackdrop(pillDropdownOpen)
                        .padding(.bottom, bottomGap)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .accessibilityHidden(navigation.detailEntry != nil)
            .allowsHitTesting(navigation.detailEntry == nil)
            if let detailEntry = navigation.detailEntry {
                NavigationStack {
                    DetailsView(entry: detailEntry, initialChapterID: navigation.detailChapterID) {
                        navigation.detailEntry = nil
                        navigation.detailChapterID = nil
                    }
                }
            }
        }
        .background(NavigationStyle.background.ignoresSafeArea())
        .fullScreenCover(isPresented: Binding(get: { !onboarded && !Self.skipsOnboarding }, set: { _ in })) {
            OnboardingView(
                openExtensions: {
                    navigation.morePath = [.extensions]
                    navigation.selection = .more
                },
                openSettings: { navigation.accountPage = .settings },
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
        .environment(\.openSettings) {
            dismissNavigationPopups()
            navigation.accountPage = .settings
        }
        .tint(NavigationStyle.accent)
        .preferredColorScheme(systemTheme ? nil : (palette.isLight ? .light : .dark))
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        ) { _ in
            searchKeyboardVisible = true
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            searchKeyboardVisible = false
        }
        .onPreferenceChange(ModalPresentedKey.self) { libraryPopupPresented = $0 }
        .onPreferenceChange(PillDropdownOpenKey.self) { pillDropdownOpen = $0 }
        .onChange(of: palette, initial: true) { _, value in
            AppTheme.shared.name = value.id
            AppTheme.shared.palette = value
        }
        .onChange(of: navigation.selection) { _, _ in
            dismissNavigationPopups()
            scrollNavigation.reset()
        }
        .onChange(of: navigation.accountPage) { _, _ in
            scrollNavigation.reset()
        }
        .onChange(of: navigation.morePath) { _, _ in
            scrollNavigation.reset()
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

/// Each page observes only its own activity. The stable reference inputs keep
/// Library data and unrelated route changes out of other tabs' view dependencies.
private struct RootTabPage: View, Equatable {
    let tab: AppTab
    let activity: TabActivity
    let navigation: RootNavigation
    let homeStore: HomeStore
    let downloadsModel: DownloadsViewModel
    let scrollNavigation: NavigationState
    let pillDropdownOpen: Bool
    @AppStorage("contentMode") private var mode: ContentMode = .all
    @AppStorage("preferences.language") private var sourceLanguage = "all"
    @Environment(LibraryStore.self) private var library

    // All parent-supplied inputs are stable references or small values. Local
    // Observation/AppStorage/environment changes still invalidate this page.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tab == rhs.tab && lhs.activity === rhs.activity
            && lhs.navigation === rhs.navigation && lhs.homeStore === rhs.homeStore
            && lhs.downloadsModel === rhs.downloadsModel
            && lhs.scrollNavigation === rhs.scrollNavigation
            && lhs.pillDropdownOpen == rhs.pillDropdownOpen
    }

    var body: some View {
        @Bindable var navigation = navigation
        return RootTabStack(tab: tab, morePath: $navigation.morePath) {
            Group {
                if activity.hasVisited { page }
                else { Color.clear }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                if tab == .home || tab == .downloads {
                    PageHeader(title: tab.title)
                        .pillBackdrop(pillDropdownOpen)
                        .background(NavigationStyle.background)
                }
            }
            .environment(\.navigationScrollChanged) { old, new in
                guard activity.isActive, !navigation.isModePickerPresented else { return }
                scrollNavigation.update(from: old, to: new)
            }
            .toolbarBackground(NavigationStyle.background, for: .navigationBar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NavigationStyle.background)
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
                    navigation.select(.library)
                    navigation.detailChapterID = nil
                    navigation.detailEntry = entry
                },
                onOpenTitle: { entry, chapterID in
                    navigation.detailChapterID = chapterID
                    navigation.detailEntry = entry
                })
        case .downloads:
            DownloadsView(model: downloadsModel, isActive: activity.isActive)
        case .library:
            LibraryView(
                mode: $mode, isActive: activity.isActive,
                downloadedIDs: downloadsModel.completedTitleIDs,
                onBrowse: { navigation.select(.browse, language: sourceLanguage) },
                onSearch: { navigation.select(.browse, language: sourceLanguage) },
                onOpen: { navigation.detailEntry = $0 })
        case .browse:
            if let model = navigation.globalSearchModel {
                SearchView(
                    model: model, openEntry: { navigation.detailEntry = $0 }, close: {},
                    isPage: true, isActive: activity.isActive,
                    readingSnapshot: homeStore.snapshot, savedEntries: library.entries
                )
                .id(ObjectIdentifier(model))
            }
        case .more:
            moreIndex
        }
    }

    private var moreIndex: some View {
        MoreIndexView()
            .safeAreaInset(edge: .top, spacing: 0) {
                PageHeader(title: "More").background(NavigationStyle.background)
            }
            .navigationDestination(for: MoreDestination.self) { destination in
                MoreDestinationView(
                    destination: destination, mode: $mode,
                    searchSource: { source in
                        let model = SearchViewModel(
                            repository: AppDependencies.searchRepository, media: source.media)
                        model.draft.sourceID = source.packageName
                        model.draft.method = .source
                        model.apply()
                        navigation.globalSearchModel = model
                        navigation.select(.browse, language: sourceLanguage)
                    }
                )
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    BackHeader(
                        title: destination.rawValue,
                        backLabel: navigation.morePath.count > 1
                            ? "Back to \(navigation.morePath[navigation.morePath.count - 2].rawValue)" : "Back to More",
                        identifier: "more.back"
                    ) {
                        if !navigation.morePath.isEmpty { navigation.morePath.removeLast() }
                    }
                    .background(NavigationStyle.background)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NavigationStyle.background)
            }
    }
}

private enum AccountPage: String, Hashable {
    case settings = "Settings"
}

@MainActor @Observable private final class RootNavigation {
    var selection: AppTab = .library { didSet { updateActivity() } }
    var accountPages: [AccountPage] = [] { didSet { updateActivity() } }
    var detailEntry: MediaEntry? { didSet { updateActivity() } }
    var detailChapterID: String?
    var morePath: [MoreDestination] = []
    var isModePickerPresented = false
    var globalSearchModel: SearchViewModel?
    let tabs = TabActivityStore()

    var accountPage: AccountPage? {
        get { accountPages.last }
        set {
            guard let newValue else {
                if !accountPages.isEmpty { accountPages = [] }
                return
            }
            if let index = accountPages.firstIndex(of: newValue) {
                accountPages = Array(accountPages.prefix(through: index))
            } else {
                accountPages.append(newValue)
            }
        }
    }

    private func updateActivity() {
        tabs.update(selection: selection, covered: accountPage != nil || detailEntry != nil)
    }

    func select(_ tab: AppTab, language: String = "all") {
        #if DEBUG
        NavigationTiming.begin(tab)
        #endif
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if tab == .browse && globalSearchModel == nil {
                globalSearchModel = SearchViewModel(
                    repository: AppDependencies.searchRepository,
                    language: language == "all" ? nil : language)
            }
            accountPage = nil
            if tab == .more { morePath = [] }
            isModePickerPresented = false
            selection = tab
        }
    }
}

/// Only More has a programmatic path. Constant empty bindings on the other
/// stacks can feed framework path updates back into the same render transaction.
private struct RootTabStack<Content: View>: View {
    let tab: AppTab
    @Binding var morePath: [MoreDestination]
    @ViewBuilder let content: Content

    var body: some View {
        if tab == .more {
            NavigationStack(path: $morePath) { content }
        } else {
            NavigationStack { content }
        }
    }
}

#if DEBUG
    #Preview {
        AppPreviewHost()
    }

    #Preview("More · index") {
        NavigationStack {
            MoreIndexView()
                .safeAreaInset(edge: .top, spacing: 0) { PageHeader(title: "More") }
                .background(NavigationStyle.background)
                .navigationDestination(for: MoreDestination.self) { destination in
                    NavigationPlaceholder(title: destination.rawValue, symbol: destination.symbol)
                }
        }
        .preferredColorScheme(.dark)
    }
#endif

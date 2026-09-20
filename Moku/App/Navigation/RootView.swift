import SwiftUI

struct RootView: View {
    @State private var pillDropdownOpen = false
    @State private var libraryPopupPresented = false
    @State private var scrollNavigation = NavigationState()
    @State private var selection: AppTab = .library
    @State private var visitedTabs: Set<AppTab> = [.library]
    let homeStore: HomeStore
    @State private var downloadsModel = DownloadsViewModel.makeDefault()
    @AppStorage("preferences.language") private var sourceLanguage = "all"
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("preferences.systemTheme") private var systemTheme = false
    @AppStorage("preferences.darkTheme") private var darkTheme = "midnight"
    @AppStorage("preferences.lightTheme") private var lightTheme = "light"
    @AppStorage("preferences.customThemes") private var customThemes = Data()
    private var effectiveTheme: String { systemTheme ? (colorScheme == .dark ? darkTheme : lightTheme) : theme }
    private var palette: NativeTheme { NativeTheme.resolve(effectiveTheme, custom: customThemes) }
    @AppStorage("preferences.theme") private var theme = "midnight"
    @AppStorage("contentMode") private var mode: ContentMode = .all
    @State private var isModePickerPresented = false
    @State private var morePath: [MoreDestination] = []
    @State private var accountPages: [AccountPage] = []
    private var accountPage: AccountPage? {
        get { accountPages.last }
        nonmutating set {
            guard let newValue else {
                accountPages = []
                return
            }
            if let index = accountPages.firstIndex(of: newValue) {
                accountPages = Array(accountPages.prefix(through: index))
            } else {
                accountPages.append(newValue)
            }
        }
    }

    private func accountBackLabel(for page: AccountPage) -> String {
        if let index = accountPages.firstIndex(of: page), index > 0 {
            return "Back to \(accountPages[index - 1].rawValue)"
        }
        return "Back to \(pageTitle(for: selection))"
    }

    private enum AccountPage: String, Hashable {
        case settings = "Settings"
    }
    @Environment(LibraryStore.self) private var library
    @State private var searchModel: SearchViewModel?
    @State private var globalSearchModel: SearchViewModel?
    @State private var searchKeyboardVisible = false
    @State private var detailEntry: MediaEntry?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { tab in
                if tab == .browse && globalSearchModel == nil {
                    globalSearchModel = SearchViewModel(
                        repository: AppDependencies.searchRepository,
                        language: sourceLanguage == "all" ? nil : sourceLanguage)
                }
                accountPage = nil
                if tab == .more { morePath = [] }
                isModePickerPresented = false
                selection = tab
            })
    }

    private var navigationContent: some View {
        ZStack {
            ForEach(AppTab.allCases.filter { $0 == selection || visitedTabs.contains($0) }) { tab in
                NavigationStack(
                    path: Binding(
                        get: { tab == .more ? morePath : [] },
                        set: { if tab == .more { morePath = $0 } }
                    )
                ) {
                    Group {
                        if tab == .more {
                            moreIndex
                        } else if tab == .home {
                            HomeView(store: homeStore)
                        } else if tab == .downloads {
                            DownloadsView(model: downloadsModel, isActive: selection == .downloads && accountPage == nil)
                        } else if tab == .library {
                            LibraryView(
                                mode: $mode, isActive: selection == .library,
                                downloadedIDs: Set(
                                    downloadsModel.entries.filter { $0.status == .completed }.map(
                                        \.titleID)),
                                onBrowse: { tabSelection.wrappedValue = .browse },
                                onSearch: {
                                    searchModel = SearchViewModel(
                                        repository: LibrarySearchRepository(
                                            entries: library.entries), isLibrary: true)
                                },
                                onOpen: { detailEntry = $0 })
                        } else if tab == .browse, let globalSearchModel {
                            SearchView(
                                model: globalSearchModel,
                                openEntry: { detailEntry = $0 }, close: {},
                                isPage: true,
                                isActive: selection == .browse && accountPage == nil
                                    && detailEntry == nil
                            )
                            .id(ObjectIdentifier(globalSearchModel))
                        } else {
                            NavigationPlaceholder(title: tab.title, symbol: tab.symbol)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if tab != .library && tab != .more && tab != .browse {
                            PageHeader(title: pageTitle(for: tab))
                                .pillBackdrop(pillDropdownOpen)
                                .background(NavigationStyle.background)
                        }
                    }
                    .environment(\.navigationScrollChanged) { old, new in
                        guard selection == tab, accountPage == nil, searchModel == nil,
                            !isModePickerPresented
                        else { return }
                        scrollNavigation.update(from: old, to: new)
                    }
                    .toolbarBackground(NavigationStyle.background, for: .navigationBar)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NavigationStyle.background)
                }
                .clipped()
                .opacity(selection == tab && accountPage == nil ? 1 : 0)
                .allowsHitTesting(selection == tab && accountPage == nil)
                .accessibilityHidden(selection != tab || accountPage != nil)
            }
            ForEach(accountPages, id: \.self) { page in
                NavigationStack {
                    Group {
                        switch page {
                        case .settings:
                            SettingsView(
                                backLabel: accountBackLabel(for: page),
                                back: { if accountPage == page { accountPages.removeLast() } },
                                openExtensions: {
                                    self.accountPage = nil
                                    morePath = [.extensions]
                                    selection = .more
                                })
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .environment(\.navigationScrollChanged) { old, new in
                        guard accountPage == page, searchModel == nil, !isModePickerPresented
                        else { return }
                        scrollNavigation.update(from: old, to: new)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NavigationStyle.background)
                }
                .opacity(accountPage == page ? 1 : 0)
                .allowsHitTesting(accountPage == page)
                .accessibilityHidden(accountPage != page)
            }
            if isModePickerPresented {
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
        scrollNavigation.isCompact && !isModePickerPresented
    }

    private var bottomNavigation: some View {
        // Transparent overlay: content continues behind the island. Scroll
        // content and indicator margins are configured independently below.
        Color.clear.frame(height: NavigationStyle.navigationInset)
            .frame(maxWidth: .infinity)

            .overlay(alignment: .bottom) {
                NavigationBar(
                    selection: tabSelection,
                    mode: $mode,
                    isModePickerPresented: $isModePickerPresented,
                    isCompact: isNavigationCompact
                )
                .opacity(
                    searchModel == nil && !libraryPopupPresented
                        && !(selection == .browse && searchKeyboardVisible) ? 1 : 0
                )
                .allowsHitTesting(
                    !libraryPopupPresented && !(selection == .browse && searchKeyboardVisible)
                )
                .accessibilityHidden(
                    libraryPopupPresented || (selection == .browse && searchKeyboardVisible))
            }
    }

    private func pageTitle(for tab: AppTab) -> String {
        switch tab {
        case .more: morePath.last?.rawValue ?? "More"
        case .library: "Library"
        default: tab.title
        }
    }

    private func dismissNavigationPopups() {
        isModePickerPresented = false
    }

    private var moreIndex: some View {
        MoreIndexView()
            .safeAreaInset(edge: .top, spacing: 0) {
                PageHeader(title: "More")
                    .background(NavigationStyle.background)
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
                        globalSearchModel = model
                        selection = .browse
                    }
                )
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    BackHeader(
                        title: destination.rawValue,
                        backLabel: morePath.count > 1
                            ? "Back to \(morePath[morePath.count - 2].rawValue)" : "Back to More",
                        identifier: "more.back"
                    ) {
                        if !morePath.isEmpty { morePath.removeLast() }
                    }
                    .background(NavigationStyle.background)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NavigationStyle.background)
            }
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
            .blur(radius: searchModel == nil || reduceTransparency ? 0 : 16)
            .allowsHitTesting(searchModel == nil)
            .accessibilityHidden(searchModel != nil)
            if let searchModel {
                ZStack {
                    (reduceTransparency ? NavigationStyle.background : Color.black.opacity(0.42))
                        .ignoresSafeArea()
                    SearchView(
                        model: searchModel,
                        openEntry: { detailEntry = $0 },
                        close: {
                            self.searchModel?.invalidate()
                            self.searchModel = nil
                        },
                        browseSources: {
                            let browse = SearchViewModel(
                                repository: AppDependencies.searchRepository,
                                language: sourceLanguage == "all" ? nil : sourceLanguage)
                            browse.query = searchModel.query
                            self.searchModel?.invalidate()
                            self.searchModel = nil
                            globalSearchModel = browse
                            selection = .browse
                            browse.submit()
                        }
                    )
                    .id(ObjectIdentifier(searchModel))
                }
                .accessibilityAddTraits(.isModal)
            }
        }
        .accessibilityHidden(detailEntry != nil)
        .allowsHitTesting(detailEntry == nil)
        .overlay {
            if let detailEntry {
                NavigationStack {
                    DetailsView(entry: detailEntry) { self.detailEntry = nil }
                }
            }
        }
        .background(NavigationStyle.background.ignoresSafeArea())
        .environment(\.openSettings) {
            dismissNavigationPopups()
            searchModel = nil
            accountPage = .settings
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
        .onChange(of: selection) { _, tab in
            visitedTabs.insert(tab)
            dismissNavigationPopups()
            scrollNavigation = NavigationState()
        }
        .onChange(of: accountPage) { _, _ in
            scrollNavigation = NavigationState()
        }
        .onChange(of: morePath) { _, _ in
            scrollNavigation = NavigationState()
        }
        .modifier(OverflowMenuHost())
        .modifier(MokuLinksHost())
    }
}

#Preview {
    AppPreviewHost()
}

#if DEBUG
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

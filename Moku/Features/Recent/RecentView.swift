import SwiftUI

struct RecentView: View {
    @Binding var mode: ContentMode
    @Environment(HomeStore.self) private var home
    @Environment(ProfileLibrary.self) private var library
    @Environment(ReaderPreferences.self) private var readerPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: RecentViewModel
    @State private var tab: Tab = .history
    @State private var viewPicker = false
    @State private var menuLevel: RadialMenuLevel = .closed
    @State private var tool: Tool?
    @State private var unreadOnly = false
    @State private var downloadedOnly = false
    @State private var draftQuery = ""
    @State private var draftUnread = false
    @State private var draftDownloaded = false
    @State private var draftMode: ContentMode = .all
    @Environment(\.navigationContentBottomInset) private var bottomInset
    private enum Tool { case search, filter, statistics }
    @State private var historySearch = ""
    @State private var updatesSearch = ""
    @State private var expanded: Set<String> = []
    @State private var confirmation: Removal?
    @State private var route: Route?
    @State private var opening = false
    @State private var didLoad = false
    @AppStorage("recent.lastUpdated") private var lastUpdated = 0.0
    private enum Tab: String, CaseIterable {
        case history = "History"
        case updates = "Updates"
        var symbol: String { self == .history ? "ClockCounterClockwise" : "ArrowsClockwise" }
    }
    private struct Removal: Identifiable {
        var entryID: String?
        var title: String
        var id: String { entryID ?? "all" }
    }
    private struct Route: Identifiable {
        let entry: MediaEntry
        let chapterID: String?
        var id: String { entry.id + (chapterID ?? "") }
    }

    init(mode: Binding<ContentMode>, model: RecentViewModel = RecentViewModel.makeDefault()) {
        _mode = mode
        _model = State(initialValue: model)
    }

    private var savedEntries: [MediaEntry] {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-recent") {
                return RecentPreviewData.entries
            }
        #endif
        return library.entries
    }

    private var query: Binding<String> { tab == .history ? $historySearch : $updatesSearch }
    private var history: [RecentHistoryTitle] {
        RecentViewModel.history(home.snapshot, query: historySearch, mode: mode)
    }
    private var updates: [RecentUpdate] {
        model.visibleUpdates(query: updatesSearch, mode: mode).filter {
            (!unreadOnly || !$0.chapter.completed) && (!downloadedOnly || $0.chapter.downloaded)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                ModeTabs(mode: $mode).pillBackdrop(viewPicker)
                controls.zIndex(3)
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if tab == .history {
                            HistoryList(
                                home: home, history: history, historySearch: historySearch,
                                expanded: expanded, opening: opening,
                                open: { open(id: $0, chapterID: $1) },
                                toggle: toggle, showStatistics: { openTool(.statistics) },
                                clear: {
                                    confirmation = Removal(
                                        entryID: $0.id,
                                        title: "Clear history for \($0.entry.title)?")
                                })
                        } else {
                            UpdateList(
                                model: model, updates: updates, updatesSearch: updatesSearch,
                                didLoad: didLoad, expanded: expanded, toggle: toggle,
                                open: { route = Route(entry: $0, chapterID: $1) }, refresh: refresh)
                        }
                    }
                    .frame(maxWidth: 700).frame(maxWidth: .infinity)
                    .padding(.horizontal, NavigationStyle.pagePadding + 12)
                    .padding(.top, 24).padding(.bottom, 16)
                }
                .firstLoadSkeleton(
                    "recent-\(tab.rawValue)",
                    loading: tab == .history ? !home.isLoaded : model.loading, style: .results
                )
                .tracksNavigationScroll()
                .scrollDismissesKeyboard(.interactively)
                .refreshable { if tab == .updates { await refresh() } else { await home.load() } }
                .accessibilityIdentifier("recent.scroll")
                .pillBackdrop(viewPicker)
                .opacity(menuLevel == .closed ? 1 : 0.18)
                .overlay {
                    if viewPicker || menuLevel != .closed {
                        Color.black.opacity(0.001).contentShape(Rectangle())
                            .onTapGesture { dismissTools() }
                            .accessibilityLabel("Dismiss Recent menu").accessibilityAddTraits(
                                .isButton)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                RadialMenu(
                    level: $menuLevel, reduceMotion: reduceMotion,
                    actions: radialActions, accessibilityPrefix: "recent", toolsTitle: "Recent"
                )
                .pillBackdrop(viewPicker)
                .padding(.trailing, max(16, (geometry.size.width - 336) / 2))
                .padding(.bottom, bottomInset + 12)
            }
        }
        .blur(radius: tool != nil || confirmation != nil ? 4 : 0)
        .allowsHitTesting(tool == nil && confirmation == nil)
        .accessibilityHidden(tool != nil || confirmation != nil)
        .overlay { if let tool { toolPopup(tool) } }
        .overlay {
            if let removal = confirmation {
                Popup(title: removal.title, close: { confirmation = nil }, preferredHeight: 240) {
                    Text("Saved titles and downloaded files will be kept.").foregroundStyle(
                        .secondary)
                } actions: {
                    Button("Cancel") { confirmation = nil }.frame(minHeight: 44)
                    Button("Clear history", role: .destructive) {
                        confirmation = nil
                        Task {
                            await home.clearHistory(entryID: removal.entryID)
                            if let error = home.storageError { model.notice = error }
                        }
                    }.frame(minHeight: 44).accessibilityIdentifier("recent.confirmClear")
                }
            }
        }
        .preference(key: ModalPresentedKey.self, value: tool != nil || confirmation != nil)
        .background(NavigationStyle.background)
        .buttonStyle(.plain)
        .tint(NavigationStyle.accent)
        .task {
            await home.load()
            await library.load()
            _ = await model.load(entries: savedEntries)
            didLoad = true
        }
        .alert(
            "Recent",
            isPresented: Binding(
                get: { model.notice != nil },
                set: { if !$0 { model.notice = nil } })
        ) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
        .onDisappear { dismissTools() }
        .fullScreenCover(
            item: $route,
            onDismiss: {
                Task { _ = await model.load(entries: savedEntries) }
            }
        ) { route in
            NavigationStack {
                DetailsView(entry: route.entry, initialChapterID: route.chapterID) {
                    self.route = nil
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recent.page")
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 12) {
            IconRail(
                title: tab.rawValue, symbol: tab.symbol, isPresented: viewPicker,
                itemCount: 1, reduceMotion: reduceMotion,
                controlIdentifier: "recent.activeView", controlLabel: "Recent view",
                toggle: {
                    menuLevel = .closed
                    viewPicker.toggle()
                }
            ) {
                ForEach(Tab.allCases.filter { $0 != tab }, id: \.self) { choice in
                    IconRailRow(title: choice.rawValue, symbol: choice.symbol, selected: false) {
                        tab = choice
                        viewPicker = false
                    }.accessibilityIdentifier("recent.view.\(choice.rawValue)")
                }
            }
            Spacer(minLength: 0)
            if !query.wrappedValue.isEmpty || unreadOnly || downloadedOnly {
                Button {
                    openTool(.filter)
                } label: {
                    Text(query.wrappedValue.isEmpty ? "Filtered" : "Search active")
                        .font(.subheadline).foregroundStyle(NavigationStyle.accent)
                }
            }
        }.padding(.horizontal, NavigationStyle.pagePadding).padding(.top, 4)
    }

    private var radialActions: [RadialAction] {
        [
            .init(title: "Search", symbol: "MagnifyingGlass") { openTool(.search) },
            .init(title: "Filter", symbol: "Funnel") { openTool(.filter) },
            tab == .history
                ? .init(
                    title: "Clear history", symbol: "Trash",
                    isEnabled: !home.snapshot.sessions.isEmpty
                ) {
                    dismissTools()
                    confirmation = Removal(title: "Clear all history?")
                }
                : .init(title: "Refresh", symbol: "ArrowsClockwise", isEnabled: !model.loading) {
                    dismissTools()
                    Task { await refresh() }
                },
        ]
    }
    private func dismissTools() {
        viewPicker = false
        menuLevel = .closed
    }
    private func openTool(_ value: Tool) {
        dismissTools()
        draftQuery = query.wrappedValue
        draftUnread = unreadOnly
        draftDownloaded = downloadedOnly
        draftMode = mode
        tool = value
    }
    private func closeTool() { tool = nil }
    private func toolPopup(_ value: Tool) -> some View {
        Popup(
            title: value == .search ? "Search" : value == .filter ? "Filters" : "Activity",
            close: closeTool, preferredHeight: value == .search ? 300 : 480
        ) {
            VStack(alignment: .leading, spacing: 24) {
                if value == .statistics {
                    statistics
                } else {
                    TextField("Search titles or chapters", text: $draftQuery)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search).padding(14)
                        .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("recent.search")
                    if value == .filter {
                        ModeTabs(mode: $draftMode)
                        if tab == .updates {
                            Toggle("Unread only", isOn: $draftUnread)
                            Toggle("Downloaded only", isOn: $draftDownloaded)
                        }
                    }
                }
            }
        } actions: {
            if value != .statistics {
                Button("Reset") {
                    draftQuery = ""
                    draftUnread = false
                    draftDownloaded = false
                    draftMode = .all
                }
                Spacer()
                Button("Cancel") { tool = nil }
                Button("Apply") {
                    query.wrappedValue = draftQuery
                    unreadOnly = draftUnread
                    downloadedOnly = draftDownloaded
                    mode = draftMode
                    tool = nil
                }.foregroundStyle(NavigationStyle.accent).frame(minHeight: 44)
            } else {
                Button("Done") { tool = nil }.frame(minHeight: 44)
            }
        }
    }

    private var statistics: some View {
        let stats = home.statistics()
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            stat("\(stats.currentStreak)", "Day streak", "Fire")
            stat("\(stats.units)", "Chapters / episodes", "BookOpen")
            stat(RecentFormat.duration(stats.minutes), "Time spent", "Clock")
            stat("\(stats.series)", "Titles", "Books")
        }.accessibilityIdentifier("recent.stats")
    }

    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            PhosphorIcon(symbol).iconSize(20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(.headline)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
    }

    private func toggle(_ id: String) { if !expanded.insert(id).inserted { expanded.remove(id) } }
    private func refresh() async {
        await library.load()
        if await model.load(entries: savedEntries, refresh: true) {
            lastUpdated = Date().timeIntervalSince1970
        }
    }
    private func open(id: String, chapterID: String?) {
        guard !opening else { return }
        opening = true
        Task {
            defer { opening = false }
            do {
                let entry = try await model.entry(id: id)
                if entry.media == .manga, let chapterID,
                    let session = home.snapshot.sessions.filter({
                        $0.entryID == id && $0.chapterID == chapterID
                    })
                    .max(by: { $0.endedAt < $1.endedAt })
                {
                    readerPreferences.document.positions[id] = ReaderPosition(
                        chapterID: chapterID, page: max(1, session.page))
                }
                route = Route(entry: entry, chapterID: chapterID)
            } catch {
                model.notice =
                    "Couldn’t open this title. Its source may no longer be installed. Try again from Library."
            }
        }
    }
}

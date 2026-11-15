import SwiftUI

struct RecentView: View {
    @Binding var mode: ContentMode
    @Environment(HomeStore.self) private var home
    @Environment(LibraryStore.self) private var library
    @Environment(ReaderPreferences.self) private var readerPreferences
    @State private var model: RecentViewModel
    @State private var tab: Tab = .history
    @State private var unreadOnly = false
    @State private var downloadedOnly = false
    @State private var showingStatistics = false
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
    }
    private struct Removal: Identifiable {
        var entryID: String?
        var title: String
        var id: String { entryID ?? "all" }
    }
    private struct Route: Identifiable, Hashable {
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
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
    @State private var history: [RecentHistoryDay] = []
    @State private var activityStats = HomeStatistics()
    private struct HistoryKey: Equatable {
        let revision: Int
        let query: String
        let mode: ContentMode
    }
    private var updates: [RecentUpdate] {
        model.visibleUpdates(query: updatesSearch, mode: mode).filter {
            (!unreadOnly || !$0.chapter.completed) && (!downloadedOnly || $0.chapter.downloaded)
        }
    }

    private var isLoading: Bool {
        tab == .history ? !home.isLoaded : (!didLoad || model.loading) && updates.isEmpty
    }
    private var isEmpty: Bool { tab == .history ? history.isEmpty : updates.isEmpty }

    var body: some View {
        List {
            if tab == .history {
                if let error = home.storageError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }
                HistoryList(
                    history: history, expanded: expanded, opening: opening,
                    open: { open(id: $0, chapterID: $1) },
                    toggle: toggle, showStatistics: { showingStatistics = true },
                    clear: {
                        confirmation = Removal(
                            entryID: $0.id, title: "Clear history for \($0.entry.title)?")
                    })
            } else {
                UpdateList(
                    model: model, updates: updates, expanded: expanded, toggle: toggle,
                    open: { route = Route(entry: $0, chapterID: $1) }, refresh: refresh)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if isLoading {
                ContentSkeleton(style: .results)
                    .padding(.horizontal, NavigationStyle.pagePadding)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if isEmpty {
                emptyState.accessibilityIdentifier("recent.empty")
            }
        }
        .searchable(text: query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search titles or chapters")
        .scrollDismissesKeyboard(.interactively)
        .refreshable { if tab == .updates { await refresh() } else { await home.load() } }
        .accessibilityIdentifier("recent.scroll")
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Recent view", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { choice in
                        Text(choice.rawValue).tag(choice)
                            .accessibilityIdentifier("recent.view.\(choice.rawValue)")
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("recent.activeView")
            }
            ToolbarItem(placement: .topBarTrailing) { toolsMenu }
        }
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible, presenting: confirmation
        ) { removal in
            Button("Clear History", role: .destructive) {
                Task {
                    await home.clearHistory(entryID: removal.entryID)
                    if let error = home.storageError { model.notice = error }
                }
            }
            .accessibilityIdentifier("recent.confirmClear")
        } message: { _ in
            Text("Saved titles and downloaded files will be kept.")
        }
        .sheet(isPresented: $showingStatistics) { statisticsSheet }
        .task {
            await home.load()
            await library.load()
        }
        .task(id: tab) {
            guard tab == .updates, !didLoad else { return }
            await library.load()
            _ = await model.load(entries: savedEntries)
            if !Task.isCancelled { didLoad = true }
        }
        .task(id: HistoryKey(revision: home.snapshotRevision, query: historySearch, mode: mode)) {
            let snapshot = home.snapshot, query = historySearch, selectedMode = mode
            let result = await Task.detached(priority: .userInitiated) {
                RecentHistoryDay.group(RecentViewModel.history(snapshot, query: query, mode: selectedMode))
            }.value
            guard !Task.isCancelled else { return }
            history = result
        }
        .task(id: showingStatistics) {
            guard showingStatistics else { return }
            let snapshot = home.snapshot
            let result = await Task.detached(priority: .userInitiated) {
                HomeStatistics.calculate(snapshot: snapshot)
            }.value
            guard !Task.isCancelled else { return }
            activityStats = result
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
        // Pushes onto whichever stack hosts History (the Settings tab, or Home).
        .navigationDestination(item: $route) { route in
            DetailsView(entry: route.entry, initialChapterID: route.chapterID) {
                self.route = nil
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NavigationStyle.background.ignoresSafeArea())
        }
        .onChange(of: route == nil) { _, closed in
            if closed, tab == .updates { Task { _ = await model.load(entries: savedEntries) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recent.page")
    }

    @ViewBuilder private var emptyState: some View {
        if !query.wrappedValue.isEmpty {
            ContentUnavailableView.search(text: query.wrappedValue)
        } else if tab == .history {
            ContentUnavailableView(
                "No History Yet", systemImage: "clock.arrow.circlepath",
                description: Text("Your reading and watching history will appear here."))
        } else {
            ContentUnavailableView {
                Label("No Recent Library Updates", systemImage: "arrow.triangle.2.circlepath")
            } description: {
                Text(unreadOnly || downloadedOnly
                     ? "No updates match the current filters."
                     : "Save titles to your Library, then check for updates.")
            } actions: {
                Button("Check for Updates") { Task { await refresh() } }
                    .disabled(model.loading)
            }
        }
    }

    private var isFiltered: Bool { mode != .all || unreadOnly || downloadedOnly }

    private var toolsMenu: some View {
        Menu {
            Picker("Type", selection: $mode) {
                ForEach(ContentMode.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.inline)
            if tab == .updates {
                Section {
                    Toggle("Unread Only", isOn: $unreadOnly)
                    Toggle("Downloaded Only", isOn: $downloadedOnly)
                }
            }
            Section {
                if tab == .updates {
                    Button("Check for Updates", systemImage: "arrow.clockwise") {
                        Task { await refresh() }
                    }
                    .disabled(model.loading)
                }
                Button("Activity Statistics", systemImage: "chart.bar") { showingStatistics = true }
            }
            if tab == .history {
                Section {
                    Button("Clear All History", systemImage: "trash", role: .destructive) {
                        confirmation = Removal(title: "Clear all history?")
                    }
                    .disabled(home.snapshot.sessions.isEmpty)
                }
            }
        } label: {
            Label(
                "History options",
                systemImage: isFiltered
                    ? "line.3.horizontal.decrease.circle.fill" : "ellipsis")
        }
        .accessibilityIdentifier("recent.tools")
    }

    private var statisticsSheet: some View {
        let stats = activityStats
        return NavigationStack {
            List {
                LabeledContent {
                    Text("\(stats.currentStreak)").monospacedDigit()
                } label: { Label("Day streak", systemImage: "flame") }
                LabeledContent {
                    Text("\(stats.units)").monospacedDigit()
                } label: { Label("Chapters / episodes", systemImage: "book") }
                LabeledContent {
                    Text(RecentFormat.duration(stats.minutes))
                } label: { Label("Time spent", systemImage: "clock") }
                LabeledContent {
                    Text("\(stats.series)").monospacedDigit()
                } label: { Label("Titles", systemImage: "books.vertical") }
            }
            .accessibilityIdentifier("recent.stats")
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingStatistics = false }
                }
            }
        }
        .presentationDetents([.medium])
        .themedColorScheme()
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

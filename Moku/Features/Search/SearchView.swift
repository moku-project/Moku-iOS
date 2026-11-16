import SwiftUI

/// Popular titles from every source, or one merged results grid while typing, as on Android.
struct SearchView: View {
    @State var model: SearchViewModel
    let openEntry: (MediaEntry) -> Void
    var isActive = true
    var openSources: () -> Void = {}
    @State private var searchPresented = false
    @AppStorage("contentMode") private var contentMode: ContentMode = .all
    @Environment(\.searchHistoryStore) private var historyStore

    private var typing: Bool { model.canSubmit }
    private var filtersActive: Bool {
        model.options.filterCount > 0 || model.options.sort != .sourceOrder
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if searchPresented { inlineFilterButton }
                if typing { results } else { popular }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            if typing { model.submit() } else { await model.loadPopular(force: true) }
        }
        .navigationTitle("Search")
        .searchable(
            text: $model.query, isPresented: $searchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: contentMode == .all
                ? "Search everything" : "Search \(contentMode.title.lowercased())"
        )
        .searchSuggestions { suggestions }
        .onSubmit(of: .search) { model.submit() }
        // The tab bar's content button chooses what Search looks for.
        .onChange(of: contentMode, initial: true) { _, mode in model.selectMode(mode) }
        // A type chosen in the filter sheet moves the content button too.
        .onChange(of: model.options.media) { _, media in
            if media != contentMode { contentMode = media }
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: panelPresented) { optionsSheet }
        .background(NavigationStyle.background.ignoresSafeArea())
        .accessibilityIdentifier("search.page")
        .onChange(of: isActive) { _, active in model.setActive(active) }
        .onAppear { model.setActive(isActive) }
        .onDisappear { model.setActive(false) }
        .task { await model.loadHistory(historyStore) }
        .task(
            id:
                "\(isActive)-\(typing)-\(model.options.media.rawValue)-\(model.options.language ?? "")"
        ) {
            guard isActive, !typing else { return }
            await model.loadPopular()
        }
        .task(id: model.panel == .filters) {
            guard model.panel == .filters else { return }
            await model.loadSources()
        }
    }

    // MARK: Content

    @ViewBuilder private var popular: some View {
        if !model.popular.isEmpty {
            if let message = model.popularMessage { note(message) }
            PosterGrid(entries: model.popular, identifier: "search.popular", open: openEntry)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("search.popularGrid")
        } else if model.popularLoading {
            ContentSkeleton(style: .library, count: 6)
        } else if let message = model.popularMessage {
            ContentUnavailableView {
                Label("Nothing to Show", systemImage: "square.grid.2x2")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.loadPopular(force: true) } }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 40)
        } else {
            ContentUnavailableView(
                "No Popular Titles", systemImage: "square.grid.2x2",
                description: Text("Your sources have nothing to show yet.")
            )
            .padding(.top, 40)
        }
    }

    @ViewBuilder private var results: some View {
        switch model.state {
        case .idle, .loading:
            ContentSkeleton(style: .library, count: 6)
        case .unavailable:
            ContentUnavailableView(
                "Search Unavailable", systemImage: "magnifyingglass",
                description: Text("Search couldn’t start. Try again in a moment.")
            )
            .padding(.top, 40)
        case .failed(let description):
            ContentUnavailableView {
                Label("Couldn’t Search", systemImage: "wifi.slash")
            } description: {
                Text(description)
            } actions: {
                Button("Try Again") { model.submit() }.buttonStyle(.bordered)
            }
            .padding(.top, 40)
        case .results(let entries):
            if entries.isEmpty {
                ContentUnavailableView.search(text: model.query).padding(.top, 40)
            } else {
                if let message = model.searchMessage { note(message) }
                if model.hiddenEmpty > 0 {
                    note(
                        "Hid \(counted(model.hiddenEmpty, "title")) with no chapters at the source."
                    )
                    .accessibilityIdentifier("search.hiddenEmpty")
                }
                PosterGrid(
                    entries: entries, identifier: "search.result", open: openEntry,
                    reachEnd: model.canLoadMore ? { await model.loadMore() } : nil)
                if model.isSearching || model.loadingMore {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var suggestions: some View {
        if model.query.isEmpty {
            ForEach(model.recentSearches.prefix(8)) { item in
                Label(item.query, systemImage: "clock.arrow.circlepath")
                    .searchCompletion(item.query)
            }
        }
    }

    // MARK: Toolbar and filters

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Sources", systemImage: "puzzlepiece.extension", action: openSources)
                .accessibilityIdentifier("search.sources")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                searchPresented = false
                model.open(.filters)
            } label: {
                Label("Filter and Sort", systemImage: filterSymbol)
            }
            .accessibilityIdentifier("search.filter")
            .accessibilityValue("\(model.options.filterCount) active filters")
        }
    }

    private var filterSymbol: String {
        filtersActive
            ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
    }

    /// The toolbar is covered while the search field is active, so filters sit above the results then.
    private var inlineFilterButton: some View {
        Button {
            model.open(.filters)
        } label: {
            Label(
                model.options.filterCount > 0
                    ? "Filters (\(model.options.filterCount))" : "Filter and Sort",
                systemImage: filterSymbol
            )
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier("search.filter.inline")
    }

    private var panelPresented: Binding<Bool> {
        Binding(
            get: { isActive && model.panel != nil },
            set: { presented in if !presented, model.panel != nil { model.cancelPanel() } })
    }

    private var optionsSheet: some View {
        NavigationStack {
            SearchOptionsView(model: model)
                .navigationTitle("Filters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.cancelPanel() }
                            .accessibilityIdentifier("search.cancelOptions")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") { model.apply() }
                            .disabled(!model.canApply)
                            .accessibilityIdentifier("search.apply")
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Reset", role: .destructive) {
                            model.resetFilters()
                            model.draft.sort = .sourceOrder
                        }
                        .accessibilityIdentifier("search.resetOptions")
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

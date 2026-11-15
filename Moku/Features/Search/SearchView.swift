import SwiftUI

struct SearchView: View {
    @State var model: SearchViewModel
    let openEntry: (MediaEntry) -> Void
    let close: () -> Void
    var isPage = false
    var isActive = true
    var readingSnapshot = HomeSnapshot()
    var savedEntries: [MediaEntry] = []
    @State private var discoveryRetry = 0
    @State private var discoverySlide = 0
    @ScaledMetric(relativeTo: .subheadline) private var shelfTextHeight: CGFloat = 72
    @ScaledMetric(relativeTo: .title3) private var shelfHeadingHeight: CGFloat = 24
    @State private var lastInteraction = Date()
    @GestureState private var interacting = false
    @State private var pageScrolling = false
    @State private var shelfScrolling = false
    @State private var searchPresented = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AppStorage("preferences.animations") private var animations = true
    @AppStorage("contentMode") private var contentMode: ContentMode = .all
    private var autoRotates: Bool {
        isDiscovery && isActive && scenePhase == .active && model.state == .idle
            && model.query.isEmpty && model.panel == nil && !searchPresented && !model.discoveryLoading
            && !interacting && !pageScrolling && !shelfScrolling
            && !reduceMotion && !voiceOver && animations && model.discoveryPairs.count > 1
    }
    private var isDiscovery: Bool { isPage && !model.isLibrary }
    private var discoveryKey: String {
        "\(isActive && !model.canSubmit)-\(model.options.media.rawValue)-\(model.options.language ?? "all")-\(model.options.sourceID ?? "")-\(readingSnapshot.sessions.count)-\(savedEntries.map(\.id).joined(separator: ","))-\(discoveryRetry)"
    }
    var browseSources: (() -> Void)? = nil
    var backToLibrary: (() -> Void)? = nil
    var customOptions: AnyView? = nil
    var prepareOptions: (() -> Void)? = nil
    var applyOptions: (() -> Void)? = nil
    var resetOptions: (() -> Void)? = nil
    @Environment(\.searchHistoryStore) private var historyStore

    private var filtersActive: Bool {
        model.options.filterCount > 0 || model.options.sort != .sourceOrder
    }

    var body: some View {
        if backToLibrary != nil {
            // Shown over the Library page: a self-contained native search screen.
            NavigationStack { page }
        } else {
            page
        }
    }

    private var page: some View {
        content
            .navigationTitle(model.isLibrary ? "Search Library" : "Search")
            .navigationBarTitleDisplayMode(backToLibrary != nil ? .inline : .automatic)
            .searchable(
                text: $model.query, isPresented: $searchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: model.isLibrary ? "Search your library" : "Titles, authors, genres"
            )
            .onSubmit(of: .search) { model.submit() }
            // The bar's content button chooses what Search looks for.
            .onChange(of: contentMode, initial: true) { _, mode in
                if !model.isLibrary { model.selectMode(mode) }
            }
            .toolbar { toolbarContent }
            .sheet(isPresented: panelPresented) { optionsSheet }
            .background(NavigationStyle.background.ignoresSafeArea())
            .accessibilityIdentifier(isPage ? "search.page" : "search.overlay")
            .onChange(of: isActive) { _, active in
                model.setActive(active)
                if !active { searchPresented = false }
            }
            .onDisappear { model.setActive(false) }
            .onAppear {
                model.setActive(isActive)
                // Searching the library starts typing right away.
                if backToLibrary != nil { searchPresented = true }
            }
            .task { await model.loadHistory(historyStore) }
            .task(id: "\(autoRotates)-\(lastInteraction.timeIntervalSinceReferenceDate)-\(discoverySlide)") {
                guard autoRotates else { return }
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard !Task.isCancelled, autoRotates else { return }
                discoverySlide = (discoverySlide + 1) % model.discoveryPairs.count
            }
            .onChange(of: model.discoveryPairs.count) { _, count in
                if discoverySlide >= count { discoverySlide = 0 }
            }
            .task(id: discoveryKey) {
                guard isDiscovery, isActive, !model.canSubmit else { return }
                await model.loadDiscovery(snapshot: readingSnapshot, saved: savedEntries, refreshToken: discoveryRetry)
            }
            .task(id: model.panel == .filters) {
                // Opening search must not boot the runtime just to populate filter choices.
                guard model.panel == .filters, customOptions == nil else { return }
                await model.loadSources()
            }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if let backToLibrary {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    searchPresented = false
                    backToLibrary()
                }
                .accessibilityLabel("Back to Library")
                .accessibilityIdentifier("search.backToLibrary")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                searchPresented = false
                prepareOptions?()
                model.open(.filters)
            } label: {
                Label(
                    "Filter and sort",
                    systemImage: filtersActive
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
            }
            .accessibilityIdentifier("search.filter")
            .accessibilityValue("\(model.options.filterCount) active filters")
        }
    }

    private var panelPresented: Binding<Bool> {
        Binding(
            get: { isActive && model.panel != nil },
            set: { presented in if !presented, model.panel != nil { model.cancelPanel() } })
    }

    private var optionsSheet: some View {
        NavigationStack {
            Group {
                if let customOptions {
                    ScrollView {
                        customOptions.padding(.horizontal, 16).padding(.vertical, 8)
                    }
                } else {
                    SearchOptionsView(model: model, showsTitle: false)
                }
            }
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancelPanel() }
                        .accessibilityIdentifier("search.cancelOptions")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyOptions?()
                        model.apply()
                    }
                    .disabled(!model.canApply)
                    .accessibilityIdentifier("search.apply")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset", role: .destructive) {
                        resetOptions?()
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

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let message = model.searchMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                if model.hiddenEmpty > 0 {
                    Text("Hid \(model.hiddenEmpty) title\(model.hiddenEmpty == 1 ? "" : "s") with no chapters at the source.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("search.hiddenEmpty")
                }
                if let error = model.historyError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
                results
                    .firstLoadSkeleton(
                        "search-\(model.isLibrary)-\(model.query.trimmingCharacters(in: .whitespacesAndNewlines))",
                        loading: model.isSearching || model.historyLoading,
                        style: model.query.isEmpty ? .settings : .results)
                if model.isSearching, case .results = model.state {
                    ContentSkeleton(style: .results, count: 2)
                }
            }
            .frame(maxWidth: 732, alignment: .top)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .onScrollPhaseChange { _, phase in pageScrolling = phase != .idle }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(TapGesture().onEnded { lastInteraction = .now })
        .simultaneousGesture(DragGesture().updating($interacting) { _, touching, _ in
            touching = true
        }.onEnded { _ in lastInteraction = .now })
    }


    @ViewBuilder private var results: some View {
        switch model.state {
        case .idle:
            if isDiscovery { discovery }
            else { recentSearches }
        case .loading:
            ContentSkeleton(style: .results)
        case .unavailable:
            ContentUnavailableView(
                "Search Unavailable", systemImage: "magnifyingglass",
                description: Text("Search couldn’t start. Try again in a moment."))
        case .failed(let description):
            ContentUnavailableView {
                Label("Couldn’t Search", systemImage: "wifi.slash")
            } description: {
                Text(description)
            } actions: {
                Button("Try Again") { model.submit() }
                    .buttonStyle(.borderedProminent)
                if model.options.filterCount > 0 {
                    Button("Clear Filters and Search") {
                        model.open(.filters)
                        model.resetFilters()
                        model.apply()
                    }
                }
            }
        case .results(let entries):
            if entries.isEmpty {
                ContentUnavailableView {
                    Label(
                        model.isLibrary ? "No Matches in Your Library" : "No Results",
                        systemImage: "magnifyingglass")
                } actions: {
                    if let browseSources, model.isLibrary {
                        Button("Browse Sources") {
                            searchPresented = false
                            browseSources()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("search.browseSources")
                    }
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        Button {
                            openEntry(entry)
                        } label: {
                            HStack(alignment: .top, spacing: 16) {
                                CoverImage(url: entry.coverURL, symbol: entry.media.symbol)
                                    .frame(width: 88, height: 126)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.title).font(.subheadline.weight(.medium))
                                        .multilineTextAlignment(.leading)
                                    Text("\(entry.media.title) · \(entry.sourceName)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { entryMenu(entry) }
                        .accessibilityIdentifier("search.result.\(entry.id)")
                        if entry.id != entries.last?.id { Divider().padding(.leading, 104) }
                    }
                    if model.canLoadMore {
                        Button {
                            Task { await model.loadMore() }
                        } label: {
                            Group {
                                if model.loadingMore { ProgressView() } else { Text("Load More") }
                            }
                            .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.loadingMore)
                        .padding(.vertical, 16)
                        .accessibilityIdentifier("search.loadMore")
                    }
                }
                .task(id: Array(entries.prefix(12).compactMap(\.coverURL))) {
                    await CoverImagePipeline.shared.prefetch(
                        entries.prefix(12).compactMap(\.coverURL))
                }
            }
        }
    }

    @ViewBuilder private func entryMenu(_ entry: MediaEntry) -> some View {
        Button("Open", systemImage: "book") { openEntry(entry) }
        Button("Copy Title", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = entry.title
        }
    }

    private var discovery: some View {
        let pairs = model.discoveryPairs
        return VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .topLeading) {
                ForEach(pairs.indices, id: \.self) { index in
                    if discoverySlide == index {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(pairs[index]) { shelf in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(shelf.title).font(.title3.weight(.semibold))
                                    .accessibilityAddTraits(.isHeader)
                                if !shelf.entries.isEmpty {
                                    discoveryShelf(shelf.entries, id: shelf.id)
                                } else if model.discoveryLoading {
                                    ContentSkeleton(style: .results, count: 2)
                                } else if shelf.id == "recommended", let message = model.recommendationMessage {
                                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                                } else if shelf.id == "popular", model.discoveryMessage == nil {
                                    Text("Your sources have no popular titles to show yet.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    }
                }
            }
            .frame(minHeight: pairs.count > 1 ? 2 * (166 + shelfTextHeight + shelfHeadingHeight + 12) + 24 : 0, alignment: .topLeading)
            .animation(reduceMotion || !animations ? nil : .easeInOut(duration: 0.5), value: discoverySlide)
            .clipped()
            .accessibilityAdjustableAction { direction in
                guard pairs.count > 1 else { return }
                lastInteraction = .now
                discoverySlide = (discoverySlide + (direction == .increment ? 1 : pairs.count - 1)) % pairs.count
            }
            CarouselBreadcrumbs(
                count: pairs.count, selection: discoverySlide, accessibilityPrefix: "search.discovery"
            ) { index in
                lastInteraction = .now
                discoverySlide = index
            }
            if let message = model.discoveryMessage {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                Button("Try Again") { discoveryRetry += 1 }
                    .accessibilityIdentifier("search.discovery.retry")
            }
            if !model.recentSearches.isEmpty { recentSearches }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.discovery")
    }

    private func discoveryShelf(_ entries: [MediaEntry], id: String) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(entries) { entry in
                    Button {
                        openEntry(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            CoverImage(url: entry.coverURL, symbol: entry.media.symbol)
                                .frame(width: 116, height: 166)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(entry.title).font(.subheadline.weight(.medium))
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Text(entry.media.title).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(width: 116, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { entryMenu(entry) }
                    .accessibilityIdentifier("search.\(id).\(entry.id)")
                }
            }
        }
        .scrollIndicators(.hidden)
        .onScrollPhaseChange { _, phase in shelfScrolling = phase != .idle }
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.recentSearches.isEmpty {
                HStack {
                    Text("Recent Searches").font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Clear") { Task { await model.removeHistory() } }
                        .accessibilityIdentifier("search.history.clearAll")
                }
                .padding(.bottom, 4)
            }
            if model.historyLoading {
                ContentSkeleton(style: .settings, count: 3)
            } else if model.recentSearches.isEmpty {
                if !isDiscovery {
                    ContentUnavailableView(
                        "No Recent Searches", systemImage: "clock.arrow.circlepath")
                }
            } else {
                let items = model.recentSearches.filter {
                    model.query.isEmpty || $0.query.localizedStandardContains(model.query)
                }
                ForEach(items) { item in
                    HStack(spacing: 0) {
                        Button {
                            searchPresented = false
                            model.query = item.query
                            model.submit()
                        } label: {
                            Label(item.query, systemImage: "clock.arrow.circlepath")
                                .lineLimit(2).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Search again for \(item.query)")
                        Button {
                            Task { await model.removeHistory(item) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote).foregroundStyle(.secondary)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel("Remove \(item.query) from search history")
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            Task { await model.removeHistory(item) }
                        }
                    }
                    if item.id != items.last?.id { Divider().padding(.leading, 36) }
                }
            }
        }
        .accessibilityIdentifier("search.history")
    }
}

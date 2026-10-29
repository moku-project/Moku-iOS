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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AppStorage("preferences.animations") private var animations = true
    private var autoRotates: Bool {
        isDiscovery && isActive && scenePhase == .active && model.state == .idle
            && model.query.isEmpty && model.panel == nil && !isInputFocused && !model.discoveryLoading
            && !interacting && !pageScrolling && !shelfScrolling
            && !reduceMotion && !voiceOver && animations && model.discoveryPairs.count > 1
    }
    private var isDiscovery: Bool { isPage && !model.isLibrary }
    private var discoveryKey: String {
        "\(isActive && !model.canSubmit)-\(model.options.media.rawValue)-\(model.options.language ?? "all")-\(model.options.sourceID ?? "")-\(readingSnapshot.sessions.count)-\(savedEntries.map(\.id).joined(separator: ","))-\(discoveryRetry)"
    }
    @State private var didFocus = false
    @Environment(\.navigationContentBottomInset) private var bottomInset
    @Environment(\.navigationContentSafeAreaAdjustment) private var safeAreaAdjustment
    @Environment(\.navigationIndicatorBottomInset) private var indicatorInset
    var browseSources: (() -> Void)? = nil
    var backToLibrary: (() -> Void)? = nil
    var customOptions: AnyView? = nil
    var prepareOptions: (() -> Void)? = nil
    var applyOptions: (() -> Void)? = nil
    var resetOptions: (() -> Void)? = nil
    @FocusState private var isInputFocused: Bool
    @Environment(\.searchHistoryStore) private var historyStore

    var body: some View {
        VStack(spacing: 16) {
            if isDiscovery {
                VStack(spacing: 0) {
                    PageHeader(title: "Search")
                    ModeTabs(mode: Binding(get: { model.options.media }, set: { model.selectMode($0) }), prefix: "search") {
                        isInputFocused = false
                    }
                }
            }
            HStack(spacing: 0) {
                if !isPage {
                    island("Close search", symbol: "X", id: "search.close", active: false) {
                        isInputFocused = false
                        model.invalidate()
                        close()
                    }
                } else {
                    PhosphorIcon("MagnifyingGlass").iconSize(22)
                        .foregroundStyle(.secondary).frame(width: 40, height: 44)
                        .accessibilityHidden(true)
                }
                searchField
                island(
                    "Filter and sort", symbol: "Sliders", id: "search.filter",
                    active: model.panel != nil || model.options.filterCount > 0
                        || model.options.sort != .sourceOrder
                ) {
                    isInputFocused = false
                    prepareOptions?()
                    model.open(.filters)
                }
                .accessibilityValue("\(model.options.filterCount) active filters")
            }
            .frame(height: NavigationStyle.navigationHeight)
            .padding(.horizontal, NavigationStyle.navigationHorizontalPadding)
            .modifier(
                FloatingSurface(
                    cornerRadius: NavigationStyle.navigationCornerRadius, tintOpacity: 0.12)
            )
            .padding(.horizontal, 16)
            if let backToLibrary {
                Button {
                    isInputFocused = false
                    backToLibrary()
                } label: {
                    PhosphorIcon("CaretLeft").iconSize(17)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Library")
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("search.backToLibrary")
                .padding(.horizontal, 16)
            }
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 12) {
                        if model.panel != nil && !isPage {
                            if let customOptions {
                                customOptions
                            } else {
                                SearchOptionsView(model: model)
                            }
                        } else {
                            if let message = model.searchMessage {
                                Text(message).font(.footnote).foregroundStyle(.secondary)
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
                    }
                    .frame(
                        maxWidth: .infinity, minHeight: geometry.size.height,
                        alignment: .top
                    )
                    .padding(.horizontal, 16)
                }
                .contentMargins(
                    .bottom,
                    isPage && !isInputFocused ? max(0, bottomInset - safeAreaAdjustment) : 0,
                    for: .scrollContent
                )
                .contentMargins(
                    .bottom, isPage && !isInputFocused ? indicatorInset : 0, for: .scrollIndicators
                )
                .onScrollPhaseChange { _, phase in pageScrolling = phase != .idle }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 12) {
                    if model.panel != nil && !isPage {
                        optionActions
                            .padding(.horizontal, 16)
                    }
                }
                .clipped()
            }

        }
        .frame(maxWidth: isPage ? 732 : 632)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isPage ? NavigationStyle.background : .clear)
        .blur(radius: isPage && model.panel != nil ? 4 : 0)
        .allowsHitTesting(!isPage || model.panel == nil)
        .accessibilityHidden(isPage && model.panel != nil)
        .overlay {
            if isPage && isActive && model.panel != nil {
                Popup(title: "Filters", close: { model.cancelPanel() }, preferredHeight: 600) {
                    if let customOptions { customOptions }
                    else { SearchOptionsView(model: model, showsTitle: false) }
                } actions: {
                    optionActions
                }
            }
        }
        .modifier(OverflowMenuHost())
        .preference(key: ModalPresentedKey.self, value: isPage && isActive && model.panel != nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isPage ? "search.page" : "search.overlay")
        .onChange(of: isActive) { _, active in
            model.setActive(active)
            if !active { isInputFocused = false }
        }
        .onDisappear { model.setActive(false) }
        .onAppear { model.setActive(isActive) }
        .task { await model.loadHistory(historyStore) }
        .simultaneousGesture(TapGesture().onEnded { lastInteraction = .now })
        .simultaneousGesture(DragGesture().updating($interacting) { _, touching, _ in
            touching = true
        }.onEnded { _ in lastInteraction = .now })
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
        .task(id: isActive) {
            guard isActive, !didFocus else { return }
            // Commit the search page before cold keyboard initialization does UIKit work.
            // A cancellable task also avoids stealing focus after the page is dismissed.
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard isActive else { return }
            didFocus = true
            isInputFocused = model.panel == nil && !isPage
        }

    }

    private var optionActions: some View {
        HStack(spacing: 12) {
            Button("Reset") {
                resetOptions?()
                model.resetFilters()
                model.draft.sort = .sourceOrder
            }
            .accessibilityIdentifier("search.resetOptions")
            Spacer(minLength: 0)
            Button("Cancel") { model.cancelPanel() }
                .accessibilityIdentifier("search.cancelOptions")
            Button("Apply") {
                applyOptions?()
                model.apply()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canApply)
            .accessibilityIdentifier("search.apply")
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .padding(12)
        .modifier(FloatingSurface(cornerRadius: 20))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            TextField("Search", text: $model.query)
                .focused($isInputFocused)
                .keyboardType(.webSearch)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    model.submit()
                    if isPage { isInputFocused = false }
                }
                .disabled(model.panel != nil)
                .accessibilityIdentifier("search.input")
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    PhosphorIcon("XCircle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("search.clear")
            }
        }
        .frame(minHeight: 44)
        .padding(.leading, 2)
        .padding(.trailing, 4)

    }

    @ViewBuilder private var results: some View {
        switch model.state {
        case .idle:
            if isDiscovery { discovery }
            else { recentSearches }
        case .loading:
            ContentSkeleton(style: .results)
        case .unavailable:
            message("Search is not available yet.", symbol: "MagnifyingGlass")
        case .failed(let description):
            VStack {
                message(description, symbol: "WifiSlash")
                Button("Try again") { model.submit() }.frame(minHeight: 44)
                if model.options.filterCount > 0 {
                    Button("Clear filters and search") {
                        model.open(.filters)
                        model.resetFilters()
                        model.apply()
                    }.frame(minHeight: 44)
                }
            }
        case .results(let entries):
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Text(model.isLibrary ? "No matches in your Library" : "No results")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let browseSources, model.isLibrary {
                        Button("Browse sources") {
                            isInputFocused = false
                            browseSources()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("search.browseSources")
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        Button {
                            isInputFocused = false
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
                        .accessibilityIdentifier("search.result.\(entry.id)")
                        if entry.id != entries.last?.id { Divider().padding(.leading, 104) }
                    }
                    if model.canLoadMore {
                        Button {
                            Task { await model.loadMore() }
                        } label: {
                            Group {
                                if model.loadingMore { ProgressView() } else { Text("Load more") }
                            }
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
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
                Button("Try again") { discoveryRetry += 1 }
                    .frame(minHeight: 44).accessibilityIdentifier("search.discovery.retry")
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
                        isInputFocused = false
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
                    .accessibilityIdentifier("search.\(id).\(entry.id)")
                }
            }
        }
        .scrollIndicators(.hidden)
        .onScrollPhaseChange { _, phase in shelfScrolling = phase != .idle }
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.recentSearches.isEmpty {
                HStack {
                    Text("Recent searches").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Clear all") { Task { await model.removeHistory() } }
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("search.history.clearAll")
                }
            }
            if model.historyLoading {
                ContentSkeleton(style: .settings, count: 3)
            } else if model.recentSearches.isEmpty {
                Text("No recent searches")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(
                    model.recentSearches.filter {
                        model.query.isEmpty || $0.query.localizedStandardContains(model.query)
                    }
                ) { item in
                    HStack(spacing: 0) {
                        Button {
                            isInputFocused = false
                            model.query = item.query
                            model.submit()
                        } label: {
                            HStack(spacing: 12) {
                                PhosphorIcon("ClockCounterClockwise").iconSize(18)
                                    .foregroundStyle(.secondary)
                                Text(item.query).font(.subheadline).lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel("Search again for \(item.query)")
                        Button {
                            Task { await model.removeHistory(item) }
                        } label: {
                            PhosphorIcon("X").iconSize(14).foregroundStyle(.secondary)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel("Remove \(item.query) from search history")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
        .accessibilityIdentifier("search.history")
    }

    private func message(_ title: String, symbol: String) -> some View {
        Label(title, phosphor: symbol)
            .font(.subheadline)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func island(
        _ title: String, symbol: String, id: String, active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            PhosphorIcon(symbol).iconSize(18)
                .foregroundStyle(active ? NavigationStyle.accent : .primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Binding var mode: ContentMode
    var isActive = true
    var downloadedIDs: Set<String> = []
    var onBrowse: () -> Void
    var onSearch: () -> Void
    var onOpen: (MediaEntry) -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(HomeStore.self) private var home
    @AppStorage("library.showAllInSaved") private var showAllInSaved = true
    @AppStorage("library.hideCompletedInSaved") private var hideCompletedInSaved = false
    @AppStorage("library.disableAutoComplete") private var disableAutoComplete = false
    @AppStorage("library.defaultTab") private var defaultTab = "Saved"
    @AppStorage("preferences.renderLimit") private var renderLimit = 48
    @State private var revealedPages = 1
    @State private var visibleItems: [LibraryItem] = []
    @State private var statsLoadedAt: Date?
    @State private var didConfigure = false
    @State private var statsRevision = 0
    @State private var preparedItemInput: ItemInput?
    private struct ItemInput: Equatable {
        let entriesRevision: Int
        let activityRevision: Int
        let statsRevision: Int
        let serverIDs: Set<String>?
        let downloaded: Set<String>
        let starred: Set<String>
    }
    private struct SelectionKey: Equatable {
        let revision: Int
        let mode: ContentMode
        let isActive: Bool
    }
    private struct RefreshKey: Equatable {
        let isActive: Bool
        let visibilityRevision: Int
    }
    @State private var itemUpdate: Task<Void, Never>?
    @State private var pendingItemInput: ItemInput?
    @State private var backendStats: [String: LibraryStats] = [:]
    @State private var model = LibraryViewModel()
    @State private var search: SearchViewModel?
    @State private var optionDraft = LibraryViewModel()
    @State private var panel: Panel?
    @State private var menuLevel: RadialMenuLevel = .closed
    @State private var foldersPresented = false
    @State private var removeSelectionConfirmed = false
    @State private var importPresented = false
    @State private var importHelpPresented = false
    @State private var newFolderPresented = false
    @Environment(\.navigationContentBottomInset) private var bottomInset
    @AppStorage("library.listLayout") private var legacyListLayout = false
    @AppStorage("library.layout") private var layoutValue = ""
    private var layout: LibraryLayout {
        LibraryLayout(rawValue: layoutValue) ?? (legacyListLayout ? .list : .grid)
    }
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("preferences.animations") private var animations = true
    private var reduceMotion: Bool { systemReduceMotion || !animations }
    typealias Panel = LibraryControls.Panel

    private var isLibraryEmpty: Bool {
        !model.items.contains { mode == .all || $0.media == mode } && model.query.isEmpty && !model.hasFilters
            && model.tab == .saved && model.folder == nil
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                LibraryHeader(mode: $mode, dismissTools: dismissTools)
                    .pillBackdrop(panel == .view || panel == .layout).zIndex(4)
                LibraryControls(
                    model: model, mode: $mode, panel: $panel,
                    menuLevel: $menuLevel, foldersPresented: $foldersPresented,
                    layoutValue: $layoutValue, layout: layout, reduceMotion: reduceMotion,
                    selectView: selectView, dismissTools: dismissTools
                ).zIndex(3)
                if let error = library.error {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry") {
                            Task { _ = await library.refreshFromServer(); await loadStats() }
                        }.disabled(library.busy)
                    }.padding(.horizontal, NavigationStyle.pagePadding)
                }
                Group {
                    if !library.loaded && library.error == nil {
                        ScrollView {
                            ContentSkeleton(style: layout.isList ? .results : .library, count: 6)
                                .padding(16)
                        }
                    } else if isLibraryEmpty {
                        GeometryReader { content in
                            ScrollView {
                                emptyLibrary
                                    .frame(maxWidth: .infinity)
                                    .frame(
                                        minHeight: max(
                                            0,
                                            content.size.height - NavigationStyle.navigationInset
                                                - max(
                                                    0,
                                                    geometry.safeAreaInsets.bottom
                                                        - NavigationStyle.navigationLowering)))
                            }
                        }
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                if model.selecting { selectionBar }
                                let allEntries = visibleItems
                                let pageSize = min(200, max(12, renderLimit))
                                let entries = Array(allEntries.prefix(revealedPages * pageSize))
                                if entries.isEmpty {
                                    VStack(spacing: 12) {
                                        Text(
                                            model.query.isEmpty && !model.hasFilters
                                                ? model.folder != nil
                                                    ? "This folder is empty"
                                                    : "No \(model.tab.rawValue.lowercased()) titles yet"
                                                : "No matching titles"
                                        )
                                        .font(.title2.bold())
                                        if model.hasFilters {
                                            Button("Clear filters") { model.clearFilters() }
                                                .buttonStyle(.plain)
                                                .foregroundStyle(NavigationStyle.accent)
                                        }
                                    }
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 180)
                                } else if layout.isList {
                                    LazyVStack(spacing: layout == .compactList ? 6 : 12) {
                                        ForEach(entries) { item in
                                            LibraryItemView(
                                                item: item, list: true, model: model,
                                                layout: layout, onOpen: onOpen)
                                        }
                                    }
                                } else {
                                    LazyVGrid(
                                        columns: Array(
                                            repeating: GridItem(.flexible(), spacing: 12),
                                            count: layout == .compactGrid ? 3 : 2),
                                        alignment: .leading, spacing: 16
                                    ) {
                                        ForEach(entries) { item in
                                            LibraryItemView(
                                                item: item, list: false, model: model,
                                                layout: layout, onOpen: onOpen)
                                        }
                                    }
                                }
                                if allEntries.count > entries.count {
                                    // Infinite scroll: reveal the next page as the end comes into view.
                                    ProgressView()
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .onAppear { revealedPages += 1 }
                                        .id(revealedPages)
                                        .accessibilityLabel("Loading more titles")
                                }
                            }
                            .padding(.horizontal, NavigationStyle.pagePadding).padding(.top, 4)
                            .padding(.bottom, 8)
                        }
                    }
                }
                .firstLoadSkeleton(
                    "library", loading: !library.loaded && library.error == nil,
                    style: layout.isList ? .results : .library
                )
                .animation(nil, value: mode)
                .pillBackdrop(panel == .mode || panel == .view || panel == .layout)
                .opacity(menuLevel == .closed ? 1 : 0.18)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: menuLevel)
                .scrollDismissesKeyboard(.interactively)
                .tracksNavigationScroll()
                .refreshable {
                    _ = await library.refreshFromServer()
                    await loadStats()
                }
                .environment(\.navigationContentBottomInset, bottomInset + 68)
                .accessibilityIdentifier("library.scroll")
                .overlay {
                    if panel == .mode || panel == .view || panel == .layout || menuLevel != .closed
                    {
                        Color.black.opacity(0.001).contentShape(Rectangle())
                            .onTapGesture { dismissTools() }
                            .accessibilityLabel("Dismiss library menu")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { dismissTools() }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                RadialMenu(
                    level: $menuLevel, reduceMotion: reduceMotion, actions: radialActions
                )
                .pillBackdrop(panel == .mode || panel == .view || panel == .layout)
                .padding(.trailing, max(16, (geometry.size.width - 336) / 2))
                .padding(.bottom, bottomInset + 12)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: panel)
            .onChange(of: isActive) { _, active in
                if active { syncItems() }
                else { cancelItemUpdate(); dismissTools() }
            }
            .onChange(of: mode) { _, _ in
                dismissTools()
                model.selected.removeAll()
                model.selecting = false
            }
            .onChange(of: model.tab) { _, _ in
                model.selected.removeAll()
            }
            .alert(
                "Library",
                isPresented: Binding(
                    get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
            ) {
                Button("OK", role: .cancel) { model.notice = nil }
            } message: {
                Text(model.notice ?? "")
            }
        }
        .onChange(of: library.entriesRevision, initial: true) { _, _ in
            syncItems()
        }
        .onChange(of: [showAllInSaved, hideCompletedInSaved, disableAutoComplete], initial: true) { _, _ in
            model.showAllInSaved = showAllInSaved
            model.hideCompletedInSaved = hideCompletedInSaved
            model.disableAutoComplete = disableAutoComplete
        }
        .task(id: SelectionKey(revision: model.resultsRevision, mode: mode, isActive: isActive)) {
            guard isActive else { return }
            let revision = model.resultsRevision
            let result = await model.prepareVisible(mode: mode)
            guard !Task.isCancelled, revision == model.resultsRevision else { return }
            if visibleItems.map(\.id) != result.map(\.id) { revealedPages = 1 }
            if visibleItems != result { visibleItems = result }
        }
        .onChange(of: renderLimit) { _, _ in revealedPages = 1 }
        .onChange(of: library.serverVisibleIDs) { _, _ in syncItems() }
        .onChange(of: home.snapshotRevision) { _, _ in syncItems() }
        .onChange(of: downloadedIDs) { _, _ in syncItems() }
        .onChange(of: library.organization.starred) { _, _ in syncItems() }
        .onChange(of: library.organization.folders, initial: true) { _, folders in
            model.folderEntryIDs = Set(folders.flatMap(\.entryIDs))
            if let id = model.folder?.id { model.folder = folders.first { $0.id == id } }
        }
        .onChange(of: mode) { _, mode in
            // A folder limited to other content types has no tab in this mode.
            if let folder = model.folder, !folder.shows(in: mode) { model.folder = nil }
        }
        .task(id: isActive ? Array(library.entries.prefix(12).compactMap(\.coverURL)) : []) {
            guard isActive else { return }
            await CoverImagePipeline.shared.prefetch(
                library.entries.prefix(12).compactMap(\.coverURL))
        }
        .task {
            await library.load()
            await library.loadOrganization()
            if !didConfigure {
                if defaultTab.hasPrefix("folder:"),
                   let folder = library.organization.folders.first(where: { "folder:\($0.id.uuidString)" == defaultTab }) {
                    // A folder chosen as the default view opens inside Saved, as when picked by hand.
                    model.tab = .saved
                    model.folder = folder
                } else {
                    model.tab = LibraryTab(rawValue: defaultTab) ?? .saved
                }
                didConfigure = true
            }
            syncItems()
        }
        .task(id: RefreshKey(isActive: isActive, visibilityRevision: library.visibilityRevision)) {
            if isActive {
                _ = await library.refreshFromServer(ifStale: true)
                await loadStats(ifStale: true)
            }
        }
        .modifier(
            LibraryFolders(
                foldersPresented: $foldersPresented, newFolderPresented: $newFolderPresented,
                model: model, mode: mode, selectSaved: { selectView(.saved) })
        )
        .overlay {
            if let search {
                SearchView(
                    model: search,
                    openEntry: { entry in
                        self.search = nil
                        onOpen(entry)
                    },
                    close: { self.search = nil },
                    isPage: true,
                    isActive: isActive,
                    backToLibrary: { self.search = nil },
                    customOptions: AnyView(LibraryFilters(optionDraft: optionDraft)),
                    prepareOptions: { copyOptions(from: model, to: optionDraft) },
                    applyOptions: { copyOptions(from: optionDraft, to: model) },
                    resetOptions: {
                        optionDraft.clearFilters()
                        optionDraft.sort = .title
                        optionDraft.ascending = true
                    }
                )
            }
        }
        .confirmationDialog(
            "Import library", isPresented: $importHelpPresented, titleVisibility: .visible
        ) {
            Button("Choose Moku library JSON") { importPresented = true }
        } message: {
            Text("Import saved titles from a Moku library.json file. Existing titles are kept.")
        }
        .fileImporter(isPresented: $importPresented, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                Task {
                    if await library.importLibrary(from: url) {
                        model.notice = "Library imported."
                    } else {
                        model.notice = library.error
                    }
                }
            case .failure(let error): model.notice = error.localizedDescription
            }
        }
        .onDisappear { cancelItemUpdate() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.page")
        .preference(
            key: ModalPresentedKey.self, value: isActive && (foldersPresented || newFolderPresented)
        )
    }

    private var emptyLibrary: some View {
        VStack(spacing: 0) {
            Text("Nothing here yet")
                .font(.title2.bold())
                .padding(.bottom, 10)
            Text("Save titles from Search, import files in Settings → Storage, or sync with Moku on your computer.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.bottom, 10)
            Button(action: onBrowse) {
                Text("Browse titles")
                    .font(.body.weight(.medium))
                    .foregroundStyle(NavigationStyle.accent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library.browse")
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .accessibilityIdentifier("library.empty")
    }

    private var selectionBar: some View {
        let ids = model.selected
        let chosen = library.entries.filter { ids.contains($0.id) }
        return HStack(spacing: 6) {
            Text("\(ids.count) selected").font(.subheadline.weight(.semibold))
            Button(ids.count == visibleItems.count ? "None" : "All") {
                model.selected = ids.count == visibleItems.count ? [] : Set(visibleItems.map(\.id))
            }
            .font(.subheadline).frame(minHeight: 44)
            Spacer()
            Group {
                Menu {
                    ForEach(library.organization.folders) { folder in
                        Button(folder.name) {
                            Task { await LibraryActions.move(ids, to: folder.id, library: library, model: model) }
                        }
                    }
                    if model.folder != nil {
                        Button("Remove from this folder", role: .destructive) {
                            Task { await LibraryActions.move(ids, to: nil, library: library, model: model) }
                        }
                    }
                } label: {
                    PhosphorIcon("FolderSimple").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Move to folder")
                Button {
                    Task { await LibraryActions.refresh(chosen, model: model) }
                } label: { PhosphorIcon("ArrowsClockwise").frame(width: 44, height: 44) }
                .accessibilityLabel("Refresh selected")
                Button(role: .destructive) {
                    removeSelectionConfirmed = true
                } label: { PhosphorIcon("Trash").frame(width: 44, height: 44) }
                .accessibilityLabel("Remove selected from library")
            }
            .disabled(ids.isEmpty)
            Button("Done") {
                model.selecting = false
                model.selected.removeAll()
            }
            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }
        .padding(.horizontal, 12)
        .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .confirmationDialog(
            "Remove \(ids.count) titles from your library?", isPresented: $removeSelectionConfirmed,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    await LibraryActions.remove(chosen, library: library, model: model)
                    model.selecting = false
                }
            }
        } message: {
            Text("You can add them back from Search at any time.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.selectionBar")
    }

    private var radialActions: [RadialAction] {
        switch menuLevel {
        case .closed: []
        case .root:
            [
                .init(title: "Search", symbol: "MagnifyingGlass") {
                    openLibrarySearch(options: false)
                },
                .init(title: "Add", symbol: "Plus") { menuLevel = .add },
                .init(title: "Update", symbol: "ArrowsClockwise") {
                    dismissTools()
                    Task { await updateLibrary() }
                },
                .init(title: "Sort", symbol: "SortAscending") { openLibrarySearch(options: true) },
                .init(title: "Filter", symbol: "Funnel") { openLibrarySearch(options: true) },
            ]
        case .add:
            [
                .init(title: "Import", symbol: "TrayArrowDown") {
                    importHelpPresented = true
                },
                .init(title: "New folder", symbol: "FolderSimplePlus") {
                    dismissTools()
                    newFolderPresented = true
                },
            ]
        }
    }

    /// Desktop "Update every series in the library": runs on the server, which
    /// skips folders excluded from updates; results land in Recent → Updates.
    private func updateLibrary() async {
        let repository = LiveRecentRepository()
        Toaster.shared.show("Updating library", detail: "New chapters will appear in Recent → Updates.", kind: .info)
        do {
            try await repository.startLibraryUpdate()
            try await Task.sleep(for: .seconds(1))
            var status = try await repository.libraryUpdateStatus()
            while status.running {
                try await Task.sleep(for: .seconds(2))
                status = try await repository.libraryUpdateStatus()
            }
            let count = status.newChapterCount
            if !status.failedTitles.isEmpty {
                Toaster.shared.show("\(status.failedTitles.count) series failed to update", detail: status.failedTitles.prefix(3).joined(separator: ", "), kind: .error)
            } else {
                Toaster.shared.show(count == 0 ? "Nothing new" : "Library update complete",
                                    detail: count == 0 ? nil : "\(count) new chapter\(count == 1 ? "" : "s") or episode\(count == 1 ? "" : "s").")
            }
            await loadStats()
        } catch is CancellationError {
        } catch {
            Toaster.shared.show("Update failed", detail: "Check your connection and try again.", kind: .error)
        }
    }

    private func selectView(_ tab: LibraryTab) {
        panel = nil
        menuLevel = .closed
        model.tab = tab
        model.folder = nil
        model.selected.removeAll()
        model.selecting = false
    }

    private func syncItems() {
        guard isActive else { return }
        let input = ItemInput(entriesRevision: library.entriesRevision, activityRevision: home.snapshotRevision,
                              statsRevision: statsRevision, serverIDs: library.serverVisibleIDs,
                              downloaded: downloadedIDs, starred: library.organization.starred)
        guard input != preparedItemInput else {
            // Inputs can revert while a different snapshot is still preparing.
            if pendingItemInput != nil { cancelItemUpdate() }
            return
        }
        guard input != pendingItemInput else { return }
        itemUpdate?.cancel()
        pendingItemInput = input
        let entries = library.entries
        let visibleIDs = library.serverVisibleIDs
        let snapshot = home.snapshot
        let stats = backendStats
        let starred = library.organization.starred
        let downloaded = downloadedIDs
        let worker = Task.detached(priority: .userInitiated) {
            var lastRead: [String: Date] = [:]
            for session in snapshot.sessions {
                if Task.isCancelled { return [LibraryItem]() }
                lastRead[session.entryID] = max(lastRead[session.entryID] ?? .distantPast, session.endedAt)
            }
            let homeEntries = Dictionary(snapshot.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            var items: [LibraryItem] = []
            items.reserveCapacity(entries.count)
            for entry in entries {
                if Task.isCancelled { return [LibraryItem]() }
                guard Int64(entry.id) == nil || visibleIDs?.contains(entry.id) != false else { continue }
                let progress = stats[entry.id]
                let saved = homeEntries[entry.id]
                items.append(LibraryItem(
                    id: entry.id, title: entry.title, media: entry.media, coverURL: entry.coverURL,
                    readUnits: progress.map { max(0, $0.chapterCount - $0.unreadCount) } ?? saved?.chapters.filter(\.isRead).count ?? 0,
                    totalUnits: progress?.chapterCount ?? saved?.chapters.count ?? 0,
                    downloaded: downloaded.contains(entry.id) || (progress?.downloadedCount ?? 0) > 0,
                    bookmarked: starred.contains(entry.id),
                    status: LibraryStatus(source: progress?.status),
                    addedAt: progress?.addedAt.flatMap(Self.date) ?? .distantPast,
                    latestUpload: progress?.latestChapter?.uploadedAt.flatMap(Self.date) ?? .distantPast,
                    tracked: !(progress?.trackLinks ?? []).isEmpty,
                    lastRead: lastRead[entry.id] ?? .distantPast))
            }
            return items
        }
        itemUpdate = Task {
            await withTaskCancellationHandler {
                let items = await worker.value
                guard !Task.isCancelled else { return }
                preparedItemInput = input
                pendingItemInput = nil
                itemUpdate = nil
                if model.items != items { model.items = items }
            } onCancel: { worker.cancel() }
        }
    }

    private func cancelItemUpdate() {
        itemUpdate?.cancel()
        itemUpdate = nil
        pendingItemInput = nil
    }

    private struct LibraryStats: Decodable, Sendable {
        struct Latest: Decodable, Sendable { let uploadedAt: String? }
        let id: String; let chapterCount: Int; let unreadCount: Int; let downloadedCount: Int
        let status: String?; let addedAt: String?; let latestChapter: Latest?
        struct Link: Decodable, Sendable { let id: String }
        let trackLinks: [Link]?
    }
    private nonisolated static func date(_ value: String) -> Date? {
        (try? Date(value, strategy: .iso8601))
            ?? (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }

    private func loadStats(ifStale: Bool = false) async {
        guard !Task.isCancelled else { return }
        if ifStale, let statsLoadedAt, Date.now.timeIntervalSince(statsLoadedAt) < 30 { return }
        guard !PreviewMode.isEnabled, library.entries.contains(where: { Int64($0.id) != nil }) else { return }
        do {
            struct Result: Decodable, Sendable { struct Page: Decodable, Sendable { let items: [LibraryStats] }; let library: Page }
            let result: Result = try await BackendAPI.shared.graphql("{ library(limit: 10000) { items { id chapterCount unreadCount downloadedCount status addedAt latestChapter { uploadedAt } trackLinks { id } } } }", requiresSourceRuntime: false)
            try Task.checkCancellation()
            statsLoadedAt = .now
            backendStats = Dictionary(result.library.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            statsRevision &+= 1
            syncItems()
        } catch { if !Task.isCancelled { model.notice = "Couldn’t refresh library progress." } }
    }

    private func copyOptions(from source: LibraryViewModel, to target: LibraryViewModel) {
        target.sort = source.sort
        target.ascending = source.ascending
        target.unreadOnly = source.unreadOnly
        target.startedOnly = source.startedOnly
        target.downloadedOnly = source.downloadedOnly
        target.bookmarkedOnly = source.bookmarkedOnly
        target.trackedOnly = source.trackedOnly
        target.status = source.status
    }

    private func openLibrarySearch(options: Bool) {
        dismissTools()
        copyOptions(from: model, to: optionDraft)
        let repository = ScopedLibrarySearchRepository {
            let items = await model.prepareVisible(mode: mode)
            let saved = library.entries
            return await Task.detached(priority: .userInitiated) {
                let entries = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                return items.compactMap { entries[$0.id] }
            }.value
        }
        let next = SearchViewModel(repository: repository, isLibrary: true)
        if options { next.open(.filters) }
        search = next
    }

    private func dismissTools() {
        panel = nil
        menuLevel = .closed
    }

}

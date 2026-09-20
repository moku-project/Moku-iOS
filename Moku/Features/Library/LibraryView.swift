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
    @State private var pageIndex = 0
    @State private var backendStats: [String: LibraryStats] = [:]
    @State private var model = LibraryViewModel()
    @State private var search: SearchViewModel?
    @State private var optionDraft = LibraryViewModel()
    @State private var panel: Panel?
    @State private var menuLevel: RadialMenuLevel = .closed
    @State private var foldersPresented = false
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
        model.scoped(to: mode).isEmpty && model.query.isEmpty && !model.hasFilters
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
                                if model.selecting {
                                    HStack {
                                        Text("\(model.selected.count) selected").font(.subheadline)
                                        Spacer()
                                        Button("Done") {
                                            model.selecting = false
                                            model.selected.removeAll()
                                        }
                                    }
                                }
                                let allEntries = model.visible(mode: mode)
                                let pageSize = min(200, max(12, renderLimit))
                                let entries = Array(allEntries.dropFirst(pageIndex * pageSize).prefix(pageSize))
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
                                if allEntries.count > pageSize {
                                    HStack {
                                        Button("Previous") { pageIndex = max(0, pageIndex - 1) }.disabled(pageIndex == 0)
                                        Spacer()
                                        Text("\(pageIndex + 1) / \((allEntries.count + pageSize - 1) / pageSize)").font(.system(size: 14)).monospacedDigit()
                                        Spacer()
                                        Button("Next") { pageIndex += 1 }.disabled((pageIndex + 1) * pageSize >= allEntries.count)
                                    }.buttonStyle(GeneralTextButtonStyle())
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
                if !active {
                    dismissTools()
                }
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
        .onChange(of: library.entries, initial: true) { _, entries in
            syncItems()
        }
        .onChange(of: [showAllInSaved, hideCompletedInSaved, disableAutoComplete], initial: true) { _, _ in
            model.showAllInSaved = showAllInSaved
            model.hideCompletedInSaved = hideCompletedInSaved
            model.disableAutoComplete = disableAutoComplete
        }
        .onChange(of: model.visible(mode: mode).map(\.id)) { _, _ in pageIndex = 0 }
        .onChange(of: renderLimit) { _, _ in pageIndex = 0 }
        .onChange(of: library.serverVisibleIDs) { _, _ in syncItems() }
        .onChange(of: home.snapshot.entries) { _, _ in syncItems() }
        .onChange(of: downloadedIDs) { _, _ in syncItems() }
        .onChange(of: library.organization.starred) { _, _ in syncItems() }
        .onChange(of: library.organization.folders, initial: true) { _, folders in
            model.folderEntryIDs = Set(folders.flatMap(\.entryIDs))
            if let id = model.folder?.id { model.folder = folders.first { $0.id == id } }
        }
        .task(id: isActive ? Array(library.entries.prefix(12).compactMap(\.coverURL)) : []) {
            guard isActive else { return }
            await CoverImagePipeline.shared.prefetch(
                library.entries.prefix(12).compactMap(\.coverURL))
        }
        .task {
            await library.load()
            await library.loadOrganization()
            _ = await library.refreshFromServer()
            model.tab = LibraryTab(rawValue: defaultTab) ?? .saved
            syncItems()
            await loadStats()
        }
        .task(id: isActive) { if isActive { _ = await library.refreshFromServer(); await loadStats() } }
        .modifier(
            LibraryFolders(
                foldersPresented: $foldersPresented, newFolderPresented: $newFolderPresented,
                model: model, selectSaved: { selectView(.saved) })
        )
        .fullScreenCover(
            isPresented: Binding(
                get: { search != nil },
                set: {
                    if !$0 {
                        search?.invalidate()
                        search = nil
                    }
                }
            )
        ) {
            if let search {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                        .overlay(Color.black.opacity(0.65)).ignoresSafeArea()
                    SearchView(
                        model: search,
                        openEntry: { entry in
                            self.search = nil
                            onOpen(entry)
                        },
                        close: { self.search = nil },
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
                .tint(NavigationStyle.accent)
                .preferredColorScheme(.dark)
                .presentationBackground(.clear)
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

    private var radialActions: [RadialAction] {
        switch menuLevel {
        case .closed: []
        case .root:
            [
                .init(title: "Search", symbol: "MagnifyingGlass") {
                    openLibrarySearch(options: false)
                },
                .init(title: "Add", symbol: "Plus") { menuLevel = .add },
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

    private func selectView(_ tab: LibraryTab) {
        panel = nil
        menuLevel = .closed
        model.tab = tab
        model.folder = nil
        model.selected.removeAll()
        model.selecting = false
    }

    private func syncItems() {
        model.items = library.entries.filter { Int64($0.id) == nil || library.serverVisibleIDs?.contains($0.id) != false }.map {
            LibraryItem(
                id: $0.id, title: $0.title, media: $0.media, coverURL: $0.coverURL,
                readUnits: backendStats[$0.id].map { max(0, $0.chapterCount - $0.unreadCount) } ?? home.entry($0.id)?.chapters.filter(\.isRead).count ?? 0,
                totalUnits: backendStats[$0.id]?.chapterCount ?? home.entry($0.id)?.chapters.count ?? 0,
                downloaded: downloadedIDs.contains($0.id) || (backendStats[$0.id]?.downloadedCount ?? 0) > 0,
                bookmarked: library.organization.starred.contains($0.id))
        }
    }

    private struct LibraryStats: Decodable, Sendable {
        let id: String; let chapterCount: Int; let unreadCount: Int; let downloadedCount: Int
    }
    private func loadStats() async {
        guard !PreviewMode.isEnabled, library.entries.contains(where: { Int64($0.id) != nil }) else { return }
        do {
            struct Result: Decodable, Sendable { struct Page: Decodable, Sendable { let items: [LibraryStats] }; let library: Page }
            let result: Result = try await BackendAPI.shared.graphql("{ library(limit: 10000) { items { id chapterCount unreadCount downloadedCount } } }", requiresSourceRuntime: false)
            backendStats = Dictionary(result.library.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            syncItems()
        } catch { model.notice = "Couldn’t refresh library progress." }
    }

    private func copyOptions(from source: LibraryViewModel, to target: LibraryViewModel) {
        target.sort = source.sort
        target.ascending = source.ascending
        target.unreadOnly = source.unreadOnly
        target.startedOnly = source.startedOnly
        target.downloadedOnly = source.downloadedOnly
        target.bookmarkedOnly = source.bookmarkedOnly
        target.status = source.status
    }

    private func openLibrarySearch(options: Bool) {
        dismissTools()
        copyOptions(from: model, to: optionDraft)
        let repository = ScopedLibrarySearchRepository {
            let entries = Dictionary(
                library.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return model.visible(mode: mode).compactMap { entries[$0.id] }
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

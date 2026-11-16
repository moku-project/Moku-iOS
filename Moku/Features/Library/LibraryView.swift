import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Binding var mode: ContentMode
    var isActive = true
    var downloadedIDs: Set<String> = []
    var onBrowse: () -> Void
    var onSearch: (String) -> Void
    var onOpen: (MediaEntry) -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(ReadingHistory.self) private var home
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
    @State private var removeSelectionConfirmed = false
    @State private var importHelpPresented = false
    @State private var newFolderPresented = false
    @State private var newFolderName = ""
    @State private var folderDraft = FolderViewModel()
    @State private var importPresented = false
    @AppStorage("preferences.modeTabs") private var savedModes = ""
    @AppStorage("library.listLayout") private var legacyListLayout = false
    @AppStorage("library.layout") private var layoutValue = ""
    private var layout: LibraryLayout {
        LibraryLayout(rawValue: layoutValue) ?? (legacyListLayout ? .list : .grid)
    }

    private var isLibraryEmpty: Bool {
        !model.items.contains { mode == .all || $0.media == mode } && model.query.isEmpty
            && !model.hasFilters
            && model.tab == .saved && model.folder == nil
    }

    private var title: String {
        if let folder = model.folder { return folder.name }
        return model.tab == .saved ? "Library" : model.tab.rawValue
    }

    private var chrome: some View {
        content
            .navigationTitle(title)
            .searchable(text: Bindable(model).query, prompt: "Search library")
            .toolbar { toolbar }
            .onChange(of: model.selecting, initial: true) { _, selecting in
                TabBarState.shared.hidden = selecting && isActive
            }
            .onChange(of: isActive) { _, active in
                if active { syncItems() } else { cancelItemUpdate() }
            }
            .onChange(of: mode) { _, _ in
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

    /// One scroll view for every state, so the large title and search field stay attached to it.
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !library.loaded && library.error == nil {
                    ContentSkeleton(style: layout.isList ? .results : .library, count: 6)
                } else if isLibraryEmpty {
                    emptyLibrary.containerRelativeFrame(.vertical) { height, _ in height * 0.75 }
                } else {
                    if let error = library.error {
                        HStack {
                            Text(error).font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Button("Retry") {
                                Task {
                                    _ = await library.refreshFromServer()
                                    await loadStats()
                                }
                            }.disabled(library.busy)
                        }
                    }
                    results
                }
            }
            .padding(.horizontal, NavigationStyle.pagePadding).padding(.top, 4)
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            _ = await library.refreshFromServer()
            await loadStats()
        }
        .accessibilityIdentifier("library.scroll")
    }

    @ViewBuilder private var results: some View {
        let allEntries = visibleItems
        let pageSize = min(200, max(12, renderLimit))
        let entries = Array(allEntries.prefix(revealedPages * pageSize))
        if entries.isEmpty {
            ContentUnavailableView {
                Label(
                    model.query.isEmpty && !model.hasFilters
                        ? model.folder != nil
                            ? "This Folder Is Empty"
                            : "No \(model.tab.rawValue) Titles"
                        : "No Matching Titles",
                    systemImage: model.query.isEmpty ? "books.vertical" : "magnifyingglass")
            } actions: {
                if model.hasFilters {
                    Button("Clear Filters") { model.clearFilters() }
                }
                if !model.query.isEmpty {
                    Button("Search Sources for “\(model.query)”") { onSearch(model.query) }
                        .accessibilityIdentifier("library.searchSources")
                }
            }
            .frame(minHeight: 280)
        } else if layout.isList {
            LazyVStack(spacing: layout == .compactList ? 6 : 12) {
                ForEach(entries) { item in
                    LibraryItemView(
                        item: item, list: true, model: model, layout: layout, onOpen: onOpen)
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
                        item: item, list: false, model: model, layout: layout, onOpen: onOpen)
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

    /// The title menu: which part of the library to show.
    @ViewBuilder private var viewMenu: some View {
        Picker(
            "View",
            selection: Binding(
                get: { model.folder == nil ? model.tab : nil },
                set: { if let tab = $0 { selectView(tab) } })
        ) {
            ForEach(LibraryTab.allCases) { tab in
                Label(tab.rawValue, systemImage: tab.systemImage).tag(Optional(tab))
            }
        }
        let folders = library.organization.folders.filter {
            $0.hidden != true && $0.shows(in: mode)
        }
        Section("Folders") {
            ForEach(folders) { folder in
                Button {
                    selectView(.saved)
                    model.folder = folder
                } label: {
                    Label(
                        folder.name,
                        systemImage: model.folder?.id == folder.id ? "checkmark" : "folder")
                }
            }
            Button {
                newFolderPresented = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if model.selecting {
            ToolbarItem(placement: .topBarLeading) {
                Button(model.selected.count == visibleItems.count ? "Deselect All" : "Select All") {
                    model.selected =
                        model.selected.count == visibleItems.count
                        ? [] : Set(visibleItems.map(\.id))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    model.selecting = false
                    model.selected.removeAll()
                }
                .fontWeight(.semibold)
            }
            ToolbarItemGroup(placement: .bottomBar) { selectionActions }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    viewMenu
                } label: {
                    Label(
                        "Library View",
                        systemImage: model.folder != nil ? "folder" : model.tab.systemImage)
                }
                .accessibilityIdentifier("library.activeView")
            }
            ToolbarItem(placement: .topBarTrailing) { optionsMenu }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Button {
                model.selecting = true
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
            .disabled(visibleItems.isEmpty)
            Button {
                Task { await updateLibrary() }
            } label: {
                Label("Update Library", systemImage: "arrow.clockwise")
            }
            Section {
                Picker(selection: Bindable(model).sort) {
                    ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                } label: {
                    Label("Sort By", systemImage: "arrow.up.arrow.down")
                    Text(model.sort.rawValue)
                }
                .pickerStyle(.menu)
                Toggle(isOn: Bindable(model).ascending) {
                    Label("Ascending", systemImage: "arrow.up")
                }
                Menu {
                    Toggle("Unread", isOn: Bindable(model).unreadOnly)
                    Toggle("Started", isOn: Bindable(model).startedOnly)
                    Toggle("Downloaded", isOn: Bindable(model).downloadedOnly)
                    Toggle("Starred", isOn: Bindable(model).bookmarkedOnly)
                    Toggle("Bookmarked Chapters", isOn: Bindable(model).chapterBookmarkedOnly)
                    Toggle("Tracked", isOn: Bindable(model).trackedOnly)
                    Picker("Status", selection: Bindable(model).status) {
                        Text("Any Status").tag(LibraryStatus?.none)
                        ForEach(LibraryStatus.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    if model.hasFilters {
                        Button("Clear Filters", role: .destructive) { model.clearFilters() }
                    }
                } label: {
                    Label(
                        "Filter",
                        systemImage: model.hasFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                }
                Picker(selection: $layoutValue) {
                    ForEach(LibraryLayout.allCases) { choice in
                        Label(choice.title, systemImage: choice.systemImage).tag(choice.rawValue)
                            .accessibilityIdentifier("library.layout.\(choice.rawValue)")
                    }
                } label: {
                    Label("Layout", systemImage: layout.systemImage)
                    Text(layout.title)
                }
                .pickerStyle(.menu)
            }
            Section {
                Button {
                    newFolderPresented = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                Button {
                    importHelpPresented = true
                } label: {
                    Label("Import Library", systemImage: "square.and.arrow.down")
                }
            }
        } label: {
            Label("Library Options", systemImage: "ellipsis")
        }
        .accessibilityIdentifier("library.options")
    }

    @ViewBuilder private var selectionActions: some View {
        let ids = model.selected
        let chosen = library.entries.filter { ids.contains($0.id) }
        Menu {
            ForEach(library.organization.folders) { folder in
                Button(folder.name) {
                    Task {
                        await LibraryActions.move(
                            ids, to: folder.id, library: library, model: model)
                    }
                }
            }
            if model.folder != nil {
                Button("Remove from This Folder", role: .destructive) {
                    Task { await LibraryActions.move(ids, to: nil, library: library, model: model) }
                }
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
        .disabled(ids.isEmpty)
        Spacer()
        Text("\(ids.count) Selected").font(.subheadline.weight(.semibold))
        Spacer()
        Button {
            Task { await LibraryActions.refresh(chosen, model: model) }
        } label: {
            Label("Refresh Selected", systemImage: "arrow.clockwise")
        }
        .disabled(ids.isEmpty)
        Button(role: .destructive) {
            removeSelectionConfirmed = true
        } label: {
            Label("Remove Selected", systemImage: "trash")
        }
        .disabled(ids.isEmpty)
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
    }

    var body: some View {
        chrome
            .onChange(of: library.entriesRevision, initial: true) { _, _ in
                syncItems()
            }
            .onChange(
                of: [showAllInSaved, hideCompletedInSaved, disableAutoComplete], initial: true
            ) { _, _ in
                model.showAllInSaved = showAllInSaved
                model.hideCompletedInSaved = hideCompletedInSaved
                model.disableAutoComplete = disableAutoComplete
            }
            .task(id: SelectionKey(revision: model.resultsRevision, mode: mode, isActive: isActive))
        {
            guard isActive else { return }
            let revision = model.resultsRevision
            let result = await model.prepareVisible(mode: mode)
            guard !Task.isCancelled, revision == model.resultsRevision else { return }
            if visibleItems.map(\.id) != result.map(\.id) { revealedPages = 1 }
            if visibleItems != result { visibleItems = result }
        }
            .onChange(of: renderLimit) { _, _ in revealedPages = 1 }
            .onChange(of: library.serverVisibleIDs) { _, _ in syncItems() }
            .onChange(of: home.revision) { _, _ in syncItems() }
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
                        let folder = library.organization.folders.first(where: {
                            "folder:\($0.id.uuidString)" == defaultTab
                        })
                    {
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
            .task(
                id: RefreshKey(isActive: isActive, visibilityRevision: library.visibilityRevision)
            ) {
                if isActive {
                    _ = await library.refreshFromServer(ifStale: true)
                    await loadStats(ifStale: true)
                }
            }
            .alert("New Folder", isPresented: $newFolderPresented) {
                TextField("Name", text: $newFolderName)
                Button("Cancel", role: .cancel) { newFolderName = "" }
                Button("Create") { createFolder() }
            } message: {
                Text("Titles you move here stay in your library.")
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
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No Saved Titles", systemImage: "books.vertical")
        } description: {
            Text("Titles you save appear here.")
        } actions: {
            Button("Browse Titles", action: onBrowse)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("library.browse")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.empty")
    }

    private func createFolder() {
        Task {
            folderDraft.name = newFolderName
            newFolderName = ""
            guard let folder = await folderDraft.create(in: library) else {
                model.notice = folderDraft.error
                return
            }
            selectView(.saved)
            model.folder = folder
        }
    }

    /// Updates every series on the server, which skips excluded folders; results land in History → Updates.
    private func updateLibrary() async {
        let repository = LiveRecentRepository()
        Toaster.shared.show(
            "Updating library", detail: "New chapters will appear in History → Updates.",
            kind: .info)
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
                Toaster.shared.show(
                    "\(counted(status.failedTitles.count, "series", "series")) failed to update",
                    detail: status.failedTitles.prefix(3).joined(separator: ", "), kind: .error)
            } else {
                Toaster.shared.show(
                    count == 0 ? "Nothing new" : "Library update complete",
                    detail: count == 0
                        ? nil
                        : "\(count) new chapter\(count == 1 ? "" : "s") or episode\(count == 1 ? "" : "s")."
                )
            }
            await loadStats()
        } catch is CancellationError {
        } catch {
            Toaster.shared.show(
                "Update failed", detail: "Check your connection and try again.", kind: .error)
        }
    }

    private func selectView(_ tab: LibraryTab) {
        model.tab = tab
        model.folder = nil
        model.selected.removeAll()
        model.selecting = false
    }

    private func syncItems() {
        guard isActive else { return }
        let input = ItemInput(
            entriesRevision: library.entriesRevision, activityRevision: home.revision,
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
        let lastRead = home.lastRead
        let stats = backendStats
        let starred = library.organization.starred
        let downloaded = downloadedIDs
        let worker = Task.detached(priority: .userInitiated) {
            var items: [LibraryItem] = []
            items.reserveCapacity(entries.count)
            for entry in entries {
                if Task.isCancelled { return [LibraryItem]() }
                guard Int64(entry.id) == nil || visibleIDs?.contains(entry.id) != false else {
                    continue
                }
                let progress = stats[entry.id]
                items.append(
                    LibraryItem(
                        id: entry.id, title: entry.title, media: entry.media,
                        coverURL: entry.coverURL,
                        readUnits: progress.map { max(0, $0.chapterCount - $0.unreadCount) } ?? 0,
                        totalUnits: progress?.chapterCount ?? 0,
                        downloaded: downloaded.contains(entry.id)
                            || (progress?.downloadedCount ?? 0) > 0,
                        bookmarked: starred.contains(entry.id),
                        status: LibraryStatus(source: progress?.status),
                        addedAt: progress?.addedAt.flatMap(Self.date) ?? .distantPast,
                        latestUpload: progress?.latestChapter?.uploadedAt.flatMap(Self.date)
                            ?? .distantPast,
                        tracked: !(progress?.trackLinks ?? []).isEmpty,
                        lastRead: lastRead[entry.id] ?? .distantPast,
                        chapterBookmarks: progress?.bookmarkedCount ?? 0))
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
            } onCancel: {
                worker.cancel()
            }
        }
    }

    private func cancelItemUpdate() {
        itemUpdate?.cancel()
        itemUpdate = nil
        pendingItemInput = nil
    }

    private struct LibraryStats: Decodable, Sendable {
        struct Latest: Decodable, Sendable { let uploadedAt: String? }
        let id: String
        let chapterCount: Int
        let unreadCount: Int
        let downloadedCount: Int
        let bookmarkedCount: Int?
        let status: String?
        let addedAt: String?
        let latestChapter: Latest?
        struct Link: Decodable, Sendable { let id: String }
        let trackLinks: [Link]?
    }
    private nonisolated static func date(_ value: String) -> Date? {
        (try? Date(value, strategy: .iso8601))
            ?? (try? Date(
                value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }

    private func loadStats(ifStale: Bool = false) async {
        guard !Task.isCancelled else { return }
        if ifStale, let statsLoadedAt, Date.now.timeIntervalSince(statsLoadedAt) < 30 { return }
        guard !PreviewMode.isEnabled, library.entries.contains(where: { Int64($0.id) != nil })
        else { return }
        do {
            struct Result: Decodable, Sendable {
                struct Page: Decodable, Sendable { let items: [LibraryStats] }
                let library: Page
            }
            let result: Result = try await BackendAPI.shared.graphql(
                "{ library(limit: 10000) { items { id chapterCount unreadCount downloadedCount bookmarkedCount status addedAt latestChapter { uploadedAt } trackLinks { id } } } }",
                requiresSourceRuntime: false)
            try Task.checkCancellation()
            statsLoadedAt = .now
            backendStats = Dictionary(
                result.library.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            statsRevision &+= 1
            syncItems()
        } catch { if !Task.isCancelled { model.notice = "Couldn’t refresh library progress." } }
    }

}

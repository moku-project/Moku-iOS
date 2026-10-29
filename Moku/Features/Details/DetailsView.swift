import SwiftUI

/// Native counterpart of desktop SeriesHeader + ChapterList.
struct DetailsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ReaderPreferences.self) private var readerPreferences
    @AppStorage("library.autoLinkOnOpen") private var autoLinkOnOpen = false
    @State private var linkedEntry: MediaEntry?
    @State private var readingChapter: Chapter?
    @State private var readingNovelChapter: Chapter?
    @AppStorage("preferences.chapterAscending") private var defaultAscending = false
    let entry: MediaEntry
    let initialChapterID: String?
    @State private var didOpenInitialChapter = false
    let back: () -> Void
    @State private var model: DetailsViewModel
    private var details: MediaDetails? { model.details }
    private var error: String? { model.error }
    private var loading: Bool { model.loading }
    @State private var saving = false
    @State private var expanded = false
    @State private var ascending = false
    @State private var chapterQuery = ""
    @State private var filteredChapters: [Chapter] = []
    private struct ChapterFilter: Equatable {
        let revision: Int
        let preferences: Data
        let query: String
        let ascending: Bool
        let sort: ChapterSort
    }
    @AppStorage("chapter.displayPreferences") private var chapterPreferences = Data()
    @AppStorage("preferences.chapterSort") private var chapterSort: ChapterSort = .number
    @State private var playingChapter: Chapter?
    @State private var selecting = false
    @State private var manageSheet: ManageSheet?
    private enum ManageSheet: String, Identifiable { case tracking, migrate, automation, metadata, cover, link; var id: Self { self } }
    @State private var selected: Set<String> = []

    init(entry: MediaEntry, initialChapterID: String? = nil, back: @escaping () -> Void) {
        self.entry = entry
        self.initialChapterID = initialChapterID
        self.back = back
        _model = State(initialValue: DetailsViewModel(entry: entry))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                let layout =
                    geometry.size.width >= 700
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
                layout {
                    metadata(wide: geometry.size.width >= 700)
                        .frame(maxWidth: geometry.size.width >= 700 ? 240 : .infinity)
                    chapters.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
        }
        .firstLoadSkeleton("details-\(entry.id)", loading: loading && details == nil, style: .results)
        .background(NavigationStyle.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            BackHeader(title: "Details", backLabel: "Back", identifier: "details.back", back: back)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: entry.id) {
            ascending = defaultAscending
            await library.load()
            await load()
            await library.loadOrganization()
            if autoLinkOnOpen { await library.autoLink(entry) }
        }
        .task(id: ChapterFilter(revision: model.chapterRevision, preferences: chapterPreferences,
                               query: chapterQuery, ascending: ascending, sort: chapterSort)) {
            let result = await ChapterPresentation.filtered(
                details?.chapters ?? [], preferences: chapterPreferences, mediaID: entry.id,
                query: chapterQuery, ascending: ascending, sort: chapterSort)
            guard !Task.isCancelled else { return }
            filteredChapters = result
        }
        .sheet(item: $linkedEntry) { linked in
            DetailsView(entry: linked) { linkedEntry = nil }
        }
        .fullScreenCover(item: $readingNovelChapter, onDismiss: refreshReadState) { chapter in
            if let details {
                NovelReaderView(
                    model: NovelReaderViewModel(
                        details: details, chapterID: chapter.id, preferences: chapterPreferences))
            }
        }
        .fullScreenCover(item: $playingChapter, onDismiss: refreshReadState) { chapter in
            if let details {
                PlayerView(
                    model: PlayerViewModel(
                        title: details.title, mediaID: details.id,
                        chapters: details.chapters, chapterID: chapter.id))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting { selectionBar }
        }
        .sheet(item: $manageSheet) { sheet in
            if let details {
                switch sheet {
                case .tracking:
                    TrackingSheet(mediaID: details.id, title: details.title, isAnime: entry.media == .anime)
                case .migrate:
                    MigrateSheet(mediaID: details.id, title: details.title, media: entry.media,
                                 currentSource: entry.sourceName) { moved in
                        // The old entry is gone; show the series on its new source.
                        library.invalidateServerVisibility()
                        linkedEntry = moved
                    }
                case .cover:
                    CoverPickerSheet(entry: entry, sourceCover: details.thumbnailUrl) {
                        Task { await model.load(refresh: true) }
                    }
                case .link:
                    SeriesLinkSheet(entry: entry)
                case .metadata:
                    MetadataSheet(mediaID: details.id, title: details.title, media: entry.media) {
                        Task { await model.load(refresh: true) }
                    }
                case .automation:
                    NavigationStack {
                        ScrollView { AutomationSettingsContent(initialMediaID: details.id).padding(20) }
                            .background(NavigationStyle.background.ignoresSafeArea())
                            .navigationTitle("Automation").navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { manageSheet = nil } } }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.details")
        .overlay {
            if readerPreferences.document.behaviour.containerized, let chapter = readingChapter,
                let details
            {
                ReaderView(
                    details: details, chapterID: chapter.id, preferences: readerPreferences,
                    onClose: {
                        readingChapter = nil
                        refreshReadState()
                    })
            }
        }
        .fullScreenCover(
            item: Binding(
                get: { readerPreferences.document.behaviour.containerized ? nil : readingChapter },
                set: {
                    if !readerPreferences.document.behaviour.containerized { readingChapter = $0 }
                }), onDismiss: refreshReadState
        ) { chapter in
            if let details {
                ReaderView(
                    details: details, chapterID: chapter.id, preferences: readerPreferences)
            }
        }
    }

    /// The server knows when a title is saved even if a content level hides it
    /// from the Library list, so prefer its answer.
    private var isSaved: Bool { details?.inLibrary ?? library.contains(entry) }

    private func cover(width: CGFloat) -> some View {
        CoverImage(
            url: details.flatMap { BackendAPI.coverURL($0.thumbnailUrl) } ?? entry.coverURL,
            symbol: entry.media.symbol
        )
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .accessibilityHidden(true)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(details?.title ?? entry.title).font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let byline = details?.byline, !byline.isEmpty {
                Text(byline).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if let status = details?.status {
                    badge(status.capitalized, accent: true)
                }
                badge(entry.sourceName)
            }
        }
    }

    private func metadata(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Desktop SeriesHeader: cover beside the title on phones, stacked in the sidebar on wide layouts.
            if wide {
                cover(width: 200)
                identity
            } else {
                HStack(alignment: .top, spacing: 16) {
                    cover(width: 118)
                    identity.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if loading && details == nil {
                ContentSkeleton(style: .settings, count: 3)
            }
            let linked = library.linkedEntries(for: entry.id)
            if !linked.isEmpty {
                Menu("Linked titles") {
                    ForEach(linked) { item in
                        Button("\(item.title) · \(item.sourceName)") { linkedEntry = item }
                    }
                }.foregroundStyle(NavigationStyle.accent)
            }
            if let genres = details?.genres, !genres.isEmpty {
                Text(genres.joined(separator: " · "))
                    .font(.caption).foregroundStyle(NavigationStyle.accent)
            }
            if let description = details?.description, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 5)
                Button(expanded ? "Show less" : "Read more") { expanded.toggle() }
                    .font(.caption).frame(minHeight: 44)
            }
            Group {
                if let target = model.continueTarget(preferences: chapterPreferences) {
                    Button { open(target.chapter) } label: {
                        Label(target.label, phosphor: entry.media == .anime ? "Play.fill" : "BookOpen.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NavigationStyle.background)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(NavigationStyle.accent, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("details.continue")
                }
                HStack(spacing: 8) {
                Button {
                    Task { await toggleLibrary() }
                } label: {
                    Label(
                        isSaved ? "In library" : "Add to library",
                        phosphor: isSaved ? "Bookmark.fill" : "Bookmark"
                    )
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 6))
                }
                .disabled(saving)
                if let details { manageMenu(details) }
                }
                if let details, !details.chapters.isEmpty {
                    let read = model.completedCount
                    HStack {
                        Text("\(read) / \(details.chapters.count) read")
                        Spacer()
                        Text("\(Int(Double(read) / Double(details.chapters.count) * 100))%")
                    }.font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(read), total: Double(details.chapters.count))
                }
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("Try again") { Task { await load(refresh: true) } }.frame(minHeight: 44)
            }
        }
    }

    private var chapters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(entry.media == .anime ? "Episodes" : "Chapters").font(
                    .subheadline.weight(.semibold))
                Text("\(details?.chapters.count ?? 0)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Picker("Sort by", selection: $chapterSort) {
                        ForEach(ChapterSort.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Direction", selection: $ascending) {
                        Text("Oldest first").tag(true)
                        Text("Newest first").tag(false)
                    }
                } label: {
                    PhosphorIcon(ascending ? "SortAscending" : "SortDescending")
                        .frame(width: 44, height: 44)
                }.accessibilityLabel("Sort chapters")
                if let details, !details.chapters.isEmpty {
                    downloadMenu(details)
                    Button {
                        selecting.toggle()
                        selected = []
                    } label: {
                        PhosphorIcon(selecting ? "X" : "CheckSquare").frame(width: 44, height: 44)
                    }.accessibilityLabel(selecting ? "Done selecting" : "Select chapters")
                    .accessibilityIdentifier("details.select")
                }
                Button {
                    Task { await load(refresh: true) }
                } label: {
                    PhosphorIcon("ArrowsClockwise").frame(width: 44, height: 44)
                }.accessibilityLabel("Refresh chapters").disabled(loading)
            }
            if let details {
                ChapterScanlatorMenu(chapters: details.chapters, mediaID: entry.id)
            }
            TextField("Filter chapters", text: $chapterQuery)
                .font(.subheadline).padding(12)
                .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 6))
            if let chapterError = model.chapterError {
                Text(chapterError).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("details.chapterError")
                Button("Retry chapters") { Task { await load(refresh: true) } }
                    .frame(minHeight: 44).disabled(loading)
            }
            if loading && (details?.chapters.isEmpty ?? true) {
                ContentSkeleton(style: .chapters, count: 6).padding(.vertical, 12)
            } else if let details {
                let filtered = filteredChapters
                if filtered.isEmpty && model.chapterError == nil {
                    VStack(alignment: .leading, spacing: 12) {
                        if !details.chapters.isEmpty {
                            Text("No chapters match your filter.")
                            Button("Clear filter") { chapterQuery = "" }
                        } else {
                            Text(model.emptyChapterMessage)
                            if let sourceURL = model.sourceURL {
                                Link("View title on MangaDex", destination: sourceURL)
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.vertical, 24)
                    .accessibilityIdentifier("details.emptyChapters")
                }
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { chapter in
                        Button {
                            if selecting {
                                if selected.contains(chapter.id) { selected.remove(chapter.id) } else { selected.insert(chapter.id) }
                            } else {
                                open(chapter)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                if selecting {
                                    PhosphorIcon(selected.contains(chapter.id) ? "CheckSquare.fill" : "Square")
                                        .foregroundStyle(selected.contains(chapter.id) ? NavigationStyle.accent : .secondary)
                                } else {
                                    PhosphorIcon(chapter.completed ? "CheckCircle.fill" : "Circle")
                                        .foregroundStyle(chapter.completed ? NavigationStyle.accent : .secondary)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chapter.label).font(.subheadline)
                                        .foregroundStyle(chapter.completed && !selecting ? .secondary : .primary)
                                    let caption = [resumeLabel(chapter), chapter.scanlator, chapter.uploadedDate].compactMap { $0 }.joined(separator: " · ")
                                    if !caption.isEmpty {
                                        Text(caption).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if chapter.downloaded {
                                    PhosphorIcon("DownloadSimple.fill").foregroundStyle(
                                        NavigationStyle.accent)
                                }
                            }.padding(.vertical, 14).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu { chapterMenu(chapter, in: filtered) }
                            .accessibilityLabel(
                                entry.media == .anime ? "Play \(chapter.label)" : chapter.label)
                            .accessibilityValue(selecting ? (selected.contains(chapter.id) ? "Selected" : "") : (chapter.completed ? "Read" : ""))
                        Divider()
                    }
                }
            }
        }
    }

    /// Desktop SeriesHeader "Manage" drawer.
    private func manageMenu(_ details: MediaDetails) -> some View {
        Menu {
            Button("Tracking", phosphor: "Broadcast") { manageSheet = .tracking }
            Button("Switch source", phosphor: "ArrowsLeftRight") { manageSheet = .migrate }
            Button("Metadata match", phosphor: "MagnifyingGlass") { manageSheet = .metadata }
            if isSaved {
                Button("Automation", phosphor: "Robot") { manageSheet = .automation }
            }
            Button("Cover image", phosphor: "Image") { manageSheet = .cover }
            let links = library.linkedEntries(for: entry.id).count
            Button(links > 0 ? "Series link (\(links))" : "Series link", phosphor: "Link") { manageSheet = .link }
            let downloaded = details.chapters.filter(\.downloaded).map(\.id)
            if !downloaded.isEmpty {
                Button("Delete downloads (\(downloaded.count))", phosphor: "Trash", role: .destructive) {
                    Task { await model.deleteDownloads(downloaded) }
                }
            }
        } label: {
            PhosphorIcon("DotsThree", size: 20)
                .frame(width: 44, height: 44)
                .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityLabel("Manage")
        .accessibilityIdentifier("details.manage")
    }

    /// Desktop chapter rows show where an unfinished chapter stopped.
    private func resumeLabel(_ chapter: Chapter) -> String? {
        guard !chapter.completed, let progress = chapter.readingProgress else { return nil }
        if entry.media == .anime, let seconds = progress.positionSeconds, seconds >= 5 {
            return "Stopped at \(Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond)))"
        }
        if entry.media != .anime, entry.media != .novels,
           let position = readerPreferences.document.positions[entry.id], position.chapterID == chapter.id, position.page > 1 {
            return "Page \(position.page)"
        }
        guard progress.progress > 0.01, progress.progress < 0.97 else { return nil }
        return "\(Int(progress.progress * 100))% read"
    }

    private func open(_ chapter: Chapter) {
        switch entry.media {
        case .anime: playingChapter = chapter
        case .novels: readingNovelChapter = chapter
        default: readingChapter = chapter
        }
    }

    /// Chapters in reading order (oldest first) after release-group preferences.
    private var readingOrder: [Chapter] {
        ChapterPresentation.readingOrder(details?.chapters ?? [], preferences: chapterPreferences, mediaID: entry.id)
    }

    @ViewBuilder private func chapterMenu(_ chapter: Chapter, in list: [Chapter]) -> some View {
        Button(chapter.completed ? "Mark as unread" : "Mark as read") {
            Task { await model.setRead([chapter.id], read: !chapter.completed) }
        }
        let order = readingOrder
        if let index = order.firstIndex(where: { $0.id == chapter.id }), index > 0 {
            let previous = Set(order[..<index].map(\.id))
            Button("Mark previous as read") { Task { await model.setRead(previous, read: true) } }
            Button("Mark previous as unread") { Task { await model.setRead(previous, read: false) } }
        }
        Divider()
        if chapter.downloaded {
            Button("Delete download", role: .destructive) { Task { await model.deleteDownloads([chapter.id]) } }
        } else {
            Button("Download") { Task { await model.download([chapter.id]) } }
        }
        if let index = order.firstIndex(where: { $0.id == chapter.id }) {
            let rest = order[index...].filter { !$0.downloaded }.map(\.id)
            if rest.count > 1 {
                Button("Download next 5 from here") { Task { await model.download(Array(rest.prefix(5))) } }
                Button("Download all from here") { Task { await model.download(rest) } }
            }
        }
        Divider()
        Button("Select") {
            selecting = true
            selected = [chapter.id]
        }
    }

    private func downloadMenu(_ details: MediaDetails) -> some View {
        let order = readingOrder
        let start = model.continueTarget(preferences: chapterPreferences)?.chapter.id
        let fromIndex = order.firstIndex { $0.id == start } ?? 0
        let ahead = order[fromIndex...].filter { !$0.downloaded }.map(\.id)
        let unread = order.filter { !$0.completed && !$0.downloaded }.map(\.id)
        let missing = order.filter { !$0.downloaded }.map(\.id)
        let downloaded = order.filter(\.downloaded).map(\.id)
        return Menu {
            Section("From the next chapter") {
                ForEach([5, 10, 25], id: \.self) { count in
                    Button("Next \(count)") { Task { await model.download(Array(ahead.prefix(count))) } }
                        .disabled(ahead.isEmpty)
                }
            }
            Button("Unread (\(unread.count))") { Task { await model.download(unread) } }.disabled(unread.isEmpty)
            Button("All (\(missing.count))") { Task { await model.download(missing) } }.disabled(missing.isEmpty)
            if !downloaded.isEmpty {
                Button("Delete all downloads (\(downloaded.count))", role: .destructive) {
                    Task { await model.deleteDownloads(downloaded) }
                }
            }
        } label: {
            PhosphorIcon("DownloadSimple").frame(width: 44, height: 44)
        }
        .accessibilityLabel("Download chapters")
        .accessibilityIdentifier("details.downloadMenu")
    }

    private var selectionBar: some View {
        let ids = selected
        let chosen = (details?.chapters ?? []).filter { ids.contains($0.id) }
        return HStack(spacing: 4) {
            Button(selected.count == filteredChapters.count ? "None" : "All") {
                selected = selected.count == filteredChapters.count ? [] : Set(filteredChapters.map(\.id))
            }
            .font(.subheadline).frame(minWidth: 44, minHeight: 44)
            Text("\(selected.count) selected").font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                barButton("Mark read", icon: "CheckCircle") { await model.setRead(ids, read: true) }
                barButton("Mark unread", icon: "Circle") { await model.setRead(ids, read: false) }
                barButton("Download", icon: "DownloadSimple") {
                    await model.download(chosen.filter { !$0.downloaded }.map(\.id))
                }
                barButton("Delete downloads", icon: "Trash") {
                    await model.deleteDownloads(chosen.filter(\.downloaded).map(\.id))
                }
            }
            .disabled(selected.isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .modifier(FloatingSurface(cornerRadius: 22))
        .padding(.horizontal, 12).padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("details.selectionBar")
    }

    private func barButton(_ label: String, icon: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                await action()
                selecting = false
                selected = []
            }
        } label: {
            PhosphorIcon(icon).frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }

    private func badge(_ text: String, accent: Bool = false) -> some View {
        Text(text).font(.caption2)
            .foregroundStyle(accent ? NavigationStyle.accent : .secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 4))
    }

    private func load(refresh: Bool = false) async {
        await model.load(refresh: refresh)
        if !didOpenInitialChapter, model.chapterError == nil, let initialChapterID,
            let details = model.details
        {
            didOpenInitialChapter = true
            if let chapter = details.chapters.first(where: { $0.id == initialChapterID }) {
                open(chapter)
            } else {
                model.error =
                    "This chapter is no longer available. You can choose another chapter below."
            }
        }
    }

    /// Readers save progress on the server; reread it so rows and Continue update.
    private func refreshReadState() {
        Task { await model.load() }
    }

    private func toggleLibrary() async {
        saving = true
        defer { saving = false }
        let saving = !isSaved
        if await library.setSaved(saving, entry: entry) {
            model.details?.inLibrary = saving
            Toaster.shared.show(saving ? "Added to library" : "Removed from library")
        } else {
            model.error = library.error ?? "Couldn’t update your library. Try again."
        }
    }
}

struct ChapterScanlatorMenu: View {
    let chapters: [Chapter]
    let mediaID: String
    @AppStorage("chapter.displayPreferences") private var data = Data()
    @State private var groups: [String] = []
    @State private var preferences = ChapterDisplayPreferences()
    private func save(_ value: ChapterDisplayPreferences) {
        var all = (try? JSONDecoder().decode([String: ChapterDisplayPreferences].self, from: data)) ?? [:]
        all[mediaID] = value
        if let encoded = try? JSONEncoder().encode(all) { data = encoded }
    }
    var body: some View {
        Group {
        if !groups.isEmpty {
            Menu {
                Picker("Preferred group", selection: Binding(
                    get: { preferences.preferred },
                    set: { var value = preferences; value.preferred = $0; save(value) }
                )) {
                    Text("Any group").tag("")
                    ForEach(groups, id: \.self) { Text($0).tag($0) }
                }
                Menu("Release groups") {
                    ForEach(groups, id: \.self) { group in
                        Toggle(group, isOn: Binding(
                            get: { preferences.included.contains(group) },
                            set: { enabled in
                                var value = preferences
                                value.included.removeAll { $0 == group }
                                if enabled { value.included.append(group) }
                                save(value)
                            }))
                    }
                }
                Toggle("Only selected groups", isOn: Binding(
                    get: { preferences.onlyIncluded },
                    set: { var value = preferences; value.onlyIncluded = $0; save(value) }))
                Menu("Hide groups") {
                    ForEach(groups, id: \.self) { group in
                        Toggle(group, isOn: Binding(
                            get: { preferences.excluded.contains(group) },
                            set: { enabled in
                                var value = preferences
                                value.excluded.removeAll { $0 == group }
                                if enabled { value.excluded.append(group) }
                                save(value)
                            }))
                    }
                }
                Button("Reset") { save(ChapterDisplayPreferences()) }
            } label: {
                Label("Scanlators", phosphor: "Funnel").font(.caption).frame(minHeight: 44)
            }
        }
        }
        .task(id: chapters) {
            let chapters = chapters
            let result = await Task.detached(priority: .userInitiated) {
                Array(Set(chapters.compactMap(\.scanlator))).sorted()
            }.value
            guard !Task.isCancelled else { return }
            groups = result
        }
        .onChange(of: data, initial: true) { _, value in
            preferences = ChapterDisplayPreferences.read(value, id: mediaID)
        }
        .onChange(of: mediaID) { _, id in
            preferences = ChapterDisplayPreferences.read(data, id: id)
        }
    }
}

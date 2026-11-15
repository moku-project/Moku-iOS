import SwiftUI

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
    @State private var allGenres = false
    @State private var ascending = false
    @State private var chapterQuery = ""
    @State private var filteredChapters: [Chapter] = []
    private struct ChapterFilter: Equatable {
        let revision: Int
        let preferences: Data
        let query: String
        let ascending: Bool
        let sort: ChapterSort
        let state: ChapterStateFilter
    }
    @AppStorage("chapter.displayPreferences") private var chapterPreferences = Data()
    @AppStorage("preferences.chapterSort") private var chapterSort: ChapterSort = .number
    /// All / Unread / Downloaded / Bookmarked, kept per title like release groups.
    @AppStorage("chapter.stateFilters") private var stateFilters = Data()
    private var stateFilter: ChapterStateFilter { ChapterStateFilter.read(stateFilters, id: entry.id) }
    private var stateFilterBinding: Binding<ChapterStateFilter> {
        Binding(get: { stateFilter }, set: { stateFilters = $0.write(into: stateFilters, id: entry.id) })
    }
    @State private var playingChapter: Chapter?
    @State private var selecting = false
    @State private var manageSheet: ManageSheet?
    private enum ManageSheet: String, Identifiable { case tracking, migrate, automation, metadata, cover, link, downloadRange; var id: Self { self } }
    @State private var selected: Set<String> = []
    /// 0 at the top, 1 once content slides under the header, 2 once the title has scrolled away.
    @State private var scrollStage = 0
    /// Set when this page is the root of a sheet or cover, which needs a Close button.
    @Environment(\.detailsShowsClose) private var showsClose
    @Environment(\.presentSourceVerification) private var verify
    @Environment(\.searchGenre) private var searchGenre
    @Environment(\.openURL) private var openURL
    @State private var jumpPresented = false
    @State private var jumpText = ""
    @State private var scrollTarget: String?

    init(entry: MediaEntry, initialChapterID: String? = nil, back: @escaping () -> Void) {
        self.entry = entry
        self.initialChapterID = initialChapterID
        self.back = back
        _model = State(initialValue: DetailsViewModel(entry: entry))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
            List {
                metadata(wide: geometry.size.width >= 700)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        Color.clear.overlay(alignment: .top) { backdrop }
                    )
                chapterRows
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .onScrollGeometryChange(for: Int.self) { geometry in
                let offset = geometry.contentOffset.y + geometry.contentInsets.top
                return offset > 180 ? 2 : offset > 4 ? 1 : 0
            } action: { _, stage in
                scrollStage = stage
            }
            .refreshable { await load(refresh: true) }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
                scrollTarget = nil
            }
            }
        }
        .firstLoadSkeleton("details-\(entry.id)", loading: loading && details == nil, style: .results)
        .background(NavigationStyle.background.ignoresSafeArea())
        .navigationTitle(details?.title ?? entry.title)
        .navigationBarTitleDisplayMode(.inline)
        // The cover wash shows through the bar until the title scrolls away.
        .toolbarBackground(scrollStage == 2 ? .automatic : .hidden, for: .navigationBar)
        .toolbar { toolbarContent }
        .alert(entry.media == .anime ? "Go to Episode" : "Go to Chapter", isPresented: $jumpPresented) {
            TextField("Number", text: $jumpText).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Go") { jump(to: jumpText) }
        } message: {
            Text("Enter a number to scroll to it in the list.")
        }
        .task(id: entry.id) {
            ascending = defaultAscending
            // The saved library only feeds links and bookmark state, so reading it never delays the title.
            let saved = Task {
                await library.load()
                await library.loadOrganization()
            }
            await load()
            await model.loadBrowserURL()
            await saved.value
            if autoLinkOnOpen { await library.autoLink(entry) }
            await model.pullTrackerIfNeeded()
        }
        .task(id: ChapterFilter(revision: model.chapterRevision, preferences: chapterPreferences,
                               query: chapterQuery, ascending: ascending, sort: chapterSort,
                               state: stateFilter)) {
            let result = await ChapterPresentation.filtered(
                details?.chapters ?? [], preferences: chapterPreferences, mediaID: entry.id,
                query: chapterQuery, ascending: ascending, sort: chapterSort, state: stateFilter)
            guard !Task.isCancelled else { return }
            filteredChapters = result
        }
        // Light poll while something here is queued or downloading; ends when downloads settle or the page goes away.
        .task(id: model.hasActiveDownloads) {
            guard model.hasActiveDownloads else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await model.refreshDownloads()
            }
        }
        .sheet(item: $linkedEntry) { linked in
            NavigationStack {
                DetailsView(entry: linked) { linkedEntry = nil }
            }
            .environment(\.detailsShowsClose, true)
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
                case .downloadRange:
                    DownloadRangeSheet(chapters: readingOrder, isAnime: entry.media == .anime) { ids in
                        Task { await model.download(ids) }
                    }
                case .metadata:
                    MetadataSheet(mediaID: details.id, title: details.title, media: entry.media) {
                        Task { await model.load(refresh: true) }
                    }
                case .automation:
                    NavigationStack {
                        AutomationSettingsContent(initialMediaID: details.id)
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

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        // The series name appears in the bar once the cover header has scrolled away.
        ToolbarItem(placement: .principal) {
            Text(details?.title ?? entry.title).font(.headline).lineLimit(1)
                .opacity(scrollStage == 2 ? 1 : 0)
                .accessibilityHidden(scrollStage < 2)
                .animation(.easeOut(duration: 0.18), value: scrollStage)
        }
        if showsClose {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: back)
                    .accessibilityIdentifier("details.back")
            }
        }
        if selecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    selecting = false
                    selected = []
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("details.select")
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) { libraryButton }
            ToolbarItem(placement: .topBarTrailing) {
                if let details { manageMenu(details) }
            }
        }
    }

    /// Prefers the server, which knows a title is saved even when a content level hides it from Library.
    private var isSaved: Bool { details?.inLibrary ?? library.contains(entry) }

    private var coverURL: URL? { details.flatMap { BackendAPI.coverURL($0.thumbnailUrl) } ?? entry.coverURL }

    private func cover(width: CGFloat) -> some View {
        CoverImage(url: coverURL, symbol: entry.media.symbol)
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .accessibilityHidden(true)
    }

    /// A soft cover wash behind the top of the page, blurred once into a flat layer so scrolling only moves a texture.
    @ViewBuilder private var backdrop: some View {
        if let coverURL {
            CoverImage(url: coverURL, contentMode: .fill, symbol: entry.media.symbol)
                .frame(height: 440)
                .blur(radius: 36, opaque: true)
                .drawingGroup()
                .opacity(0.4)
                .mask(LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3),
                            .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom))
                .offset(y: -140)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// the source reports content rating and original language as genres; they read better as badges.
    private var tags: (badges: [String], genres: [String]) {
        var badges: [String] = []
        var genres: [String] = []
        for genre in details?.genres ?? [] {
            let lower = genre.lowercased()
            if lower.hasPrefix("content rating:") {
                let rating = genre.dropFirst("content rating:".count).trimmingCharacters(in: .whitespaces)
                if !rating.isEmpty, rating.lowercased() != "safe" { badges.append(rating.capitalized) }
            } else if Self.languageTags.contains(lower) {
                badges.append(genre)
            } else {
                genres.append(genre)
            }
        }
        return (badges, genres)
    }

    private static let languageTags: Set<String> = [
        "japanese", "korean", "chinese", "english", "indonesian", "thai", "vietnamese", "spanish",
        "french", "portuguese", "russian", "german", "italian", "filipino", "arabic",
    ]

    private var identity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(details?.title ?? entry.title).font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let byline = details?.byline, !byline.isEmpty {
                Text(byline).font(.subheadline).foregroundStyle(.secondary)
            }
            ChipFlow(spacing: 6) {
                if let status = details?.status {
                    badge(status.capitalized, accent: true)
                }
                badge(entry.sourceName)
                ForEach(tags.badges, id: \.self) { badge($0) }
            }
        }
    }

    private func metadata(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                cover(width: wide ? 180 : 128)
                identity.frame(maxWidth: .infinity, alignment: .leading)
            }
            if loading && details == nil {
                ContentSkeleton(style: .settings, count: 3)
            }
            let linked = library.linkedEntries(for: entry.id)
            if !linked.isEmpty {
                Menu {
                    ForEach(linked) { item in
                        Menu("\(item.title) · \(item.sourceName)") {
                            Button("Open", systemImage: "arrow.up.forward.square") { linkedEntry = item }
                            Button("Open in Browser", systemImage: "safari") { openInBrowser(item) }
                        }
                    }
                } label: {
                    Label("Linked Titles", systemImage: "link")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
            let genres = tags.genres
            if !genres.isEmpty {
                // A few genres say enough; the rest stay one tap away.
                let shown = allGenres ? genres : Array(genres.prefix(4))
                ChipFlow(spacing: 6) {
                    ForEach(shown, id: \.self) { genre in
                        if let searchGenre {
                            Button {
                                if showsClose { back() }
                                searchGenre(genre)
                            } label: { genreChip(genre) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Searches for titles in this genre")
                        } else {
                            genreChip(genre)
                        }
                    }
                    if genres.count > 4 {
                        Button {
                            withAnimation(.snappy(duration: 0.25)) { allGenres.toggle() }
                        } label: {
                            Text(allGenres ? "Less" : "+\(genres.count - shown.count)").font(.footnote.weight(.semibold))
                                .foregroundStyle(NavigationStyle.accent)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.fill.tertiary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(allGenres ? "Show fewer genres" : "Show all \(genres.count) genres")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Genres")
            }
            if let description = details?.description, !description.isEmpty {
                summary(description)
            }
            actions
            if let error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("Try Again") { Task { await load(refresh: true) } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func genreChip(_ genre: String) -> some View {
        Text(genre).font(.footnote).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.fill.tertiary, in: Capsule())
    }

    /// Three lines that fade out; tapping anywhere on the text opens the rest.
    private func summary(_ text: String) -> some View {
        let long = text.count > 160 || text.filter(\.isNewline).count > 1
        return Button {
            withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(expanded || !long ? nil : 3)
                    .mask {
                        LinearGradient(
                            stops: [.init(color: .black, location: 0),
                                    .init(color: .black, location: expanded || !long ? 1 : 0.6),
                                    .init(color: expanded || !long ? .black : .clear, location: 1)],
                            startPoint: .top, endPoint: .bottom)
                    }
                if long {
                    Text(expanded ? "Show less" : "Read more")
                        .font(.caption.weight(.semibold)).foregroundStyle(NavigationStyle.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!long)
        .accessibilityHint(long ? (expanded ? "Shows less" : "Shows the full description") : "")
    }

    /// The main read button, with a placeholder until chapters arrive so the header doesn't jump.
    @ViewBuilder private var actions: some View {
        let target = model.continueTarget(preferences: chapterPreferences)
        if target != nil || (loading && (details?.chapters.isEmpty ?? true)) {
            Button {
                if let target { open(target.chapter) }
            } label: {
                // An HStack, not a Label: list rows pin a Label's icon to a leading column.
                HStack(spacing: 8) {
                    Image(systemName: entry.media == .anime ? "play.fill" : "book.fill")
                    Text(target?.label ?? "Loading chapters")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .disabled(target == nil)
            .accessibilityIdentifier("details.continue")
        } else if !isSaved {
            Button {
                Task { await toggleLibrary() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bookmark")
                    Text("Add to Library")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
            .disabled(saving)
        }
        if let details, model.completedCount > 0, !details.chapters.isEmpty {
            let read = model.completedCount, total = details.chapters.count
            VStack(spacing: 6) {
                HStack {
                    Text("\(read) of \(total) read")
                    Spacer()
                    Text("\(Int(Double(read) / Double(total) * 100))%")
                }.font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(read), total: Double(total)).tint(NavigationStyle.accent)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var libraryButton: some View {
        Button {
            Task { await toggleLibrary() }
        } label: {
            Label(
                isSaved ? "In Library" : "Add to Library",
                systemImage: isSaved ? "bookmark.fill" : "bookmark")
        }
        .disabled(saving)
        .accessibilityLabel(isSaved ? "In library" : "Add to library")
        .accessibilityIdentifier("details.library")
    }

    @ViewBuilder private var chapterRows: some View {
        chaptersHeader
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        if let details {
            ChapterScanlatorMenu(chapters: details.chapters, mediaID: entry.id)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        if (details?.chapters.count ?? 0) > 20 || !chapterQuery.isEmpty {
            chapterFilterField
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        if let chapterError = model.chapterError {
            VStack(alignment: .leading, spacing: 8) {
                Text(chapterError).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("details.chapterError")
                HStack {
                    if model.sourceChallenge, let extensionID = entry.extensionID {
                        Button("Verify in Browser") {
                            verify(extensionID: extensionID, url: model.sourceURL, sourceName: entry.sourceName) {
                                Task { await load(refresh: true) }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("details.verify")
                    }
                    Button("Retry Chapters") { Task { await load(refresh: true) } }
                        .buttonStyle(.bordered).disabled(loading)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        if loading && (details?.chapters.isEmpty ?? true) {
            ContentSkeleton(style: .chapters, count: 6)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else if let details {
            let filtered = filteredChapters
            if filtered.isEmpty && model.chapterError == nil {
                Group {
                    if !details.chapters.isEmpty {
                        ContentUnavailableView {
                            Label("No Matching Chapters", systemImage: "magnifyingglass")
                        } description: {
                            Text("No chapters match your filter.")
                        } actions: {
                            Button("Clear Filter") {
                                chapterQuery = ""
                                stateFilterBinding.wrappedValue = .all
                            }
                        }
                    } else {
                        ContentUnavailableView {
                            Label(
                                entry.media == .anime ? "No Episodes" : "No Chapters",
                                systemImage: "list.bullet")
                        } description: {
                            Text(model.emptyChapterMessage)
                        } actions: {
                            if let sourceURL = model.sourceURL {
                                Link("View Title on the source", destination: sourceURL)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("details.emptyChapters")
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            ForEach(filtered) { chapter in
                chapterRow(chapter, in: filtered)
                    .accessibilityIdentifier("details.chapter.\(chapter.id)")
            }
        }
    }

    private var chaptersHeader: some View {
        HStack(spacing: 4) {
            Text(entry.media == .anime ? "Episodes" : "Chapters").font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("\(details?.chapters.count ?? 0)").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Menu {
                Picker("Sort by", selection: $chapterSort) {
                    ForEach(ChapterSort.allCases) { Text($0.title).tag($0) }
                }
                Picker("Direction", selection: $ascending) {
                    Text("Oldest First").tag(true)
                    Text("Newest First").tag(false)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Sort chapters")
            Menu {
                Picker("Show", selection: stateFilterBinding) {
                    ForEach(ChapterStateFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.symbol).tag(filter)
                    }
                }
                .pickerStyle(.inline)
                Toggle("Hide Duplicate Chapters", systemImage: "square.on.square", isOn: hideDuplicatesBinding)
            } label: {
                Image(systemName: stateFilter == .all
                      ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Chapter filter")
            .accessibilityValue(stateFilter.title)
            .accessibilityIdentifier("details.chapterFilter")
            if let details, !details.chapters.isEmpty {
                Button {
                    selecting.toggle()
                    selected = []
                } label: {
                    Image(systemName: selecting ? "checkmark.circle.fill" : "checkmark.circle")
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(selecting ? "Done selecting" : "Select chapters")
            }
            Menu {
                if let details, !details.chapters.isEmpty {
                    downloadMenu(details)
                    Button(entry.media == .anime ? "Go to Episode…" : "Go to Chapter…", systemImage: "list.number") {
                        jumpText = ""
                        jumpPresented = true
                    }
                }
                Button("Refresh Chapters", systemImage: "arrow.clockwise") {
                    Task { await load(refresh: true) }
                }.disabled(loading)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("More chapter actions")
            .accessibilityIdentifier("details.chapterActions")
        }
        .buttonStyle(.borderless)
    }

    private var hideDuplicatesBinding: Binding<Bool> {
        Binding(
            get: { ChapterDisplayPreferences.read(chapterPreferences, id: entry.id).hideDuplicates },
            set: { value in
                var all = (try? JSONDecoder().decode([String: ChapterDisplayPreferences].self, from: chapterPreferences)) ?? [:]
                var current = all[entry.id] ?? ChapterDisplayPreferences()
                current.hideDuplicates = value
                all[entry.id] = current
                if let encoded = try? JSONEncoder().encode(all) { chapterPreferences = encoded }
            })
    }

    /// Scrolls to the visible chapter with this number, or the closest one.
    private func jump(to text: String) {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let number = Double(normalized) else { return }
        let numbered = filteredChapters.filter { $0.number != nil }
        guard let target = numbered.first(where: { $0.number == number })
            ?? numbered.min(by: { abs($0.number! - number) < abs($1.number! - number) })
        else {
            Toaster.shared.show("No chapter \(number.formatted()) in this list", kind: .info)
            return
        }
        scrollTarget = target.id
    }

    private func openInBrowser(_ item: MediaEntry) {
        Task {
            if let url = await SourceLink.url(mediaID: item.id) {
                openURL(url)
            } else {
                Toaster.shared.show("This source has no web page for the title", kind: .info)
            }
        }
    }

    private var chapterFilterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter chapters", text: $chapterQuery)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !chapterQuery.isEmpty {
                Button { chapterQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func chapterRow(_ chapter: Chapter, in filtered: [Chapter]) -> some View {
        let isSelected = selected.contains(chapter.id)
        return Button {
            if selecting {
                if isSelected { selected.remove(chapter.id) } else { selected.insert(chapter.id) }
            } else {
                open(chapter)
            }
        } label: {
            HStack(spacing: 12) {
                if selecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? NavigationStyle.accent : .secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if chapter.bookmarked {
                            Image(systemName: "bookmark.fill")
                                .font(.footnote)
                                .foregroundStyle(NavigationStyle.accent)
                                .accessibilityHidden(true)
                        }
                        Text(chapter.label).font(.body)
                            .foregroundStyle(chapter.completed && !selecting ? .secondary : .primary)
                    }
                    let caption = [resumeLabel(chapter), chapter.scanlator, chapter.uploadedDate].compactMap { $0 }.joined(separator: " · ")
                    if !caption.isEmpty {
                        Text(caption).font(.caption).foregroundStyle(.secondary)
                    }
                    if let progress = chapter.partialProgress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(NavigationStyle.accent)
                            .frame(maxWidth: 220)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                    }
                }
                Spacer(minLength: 0)
                ChapterDownloadIndicator(state: chapter.downloadState)
                if chapter.completed && !selecting {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !selecting {
                Button {
                    Task { await model.setRead([chapter.id], read: !chapter.completed) }
                } label: {
                    Label(
                        chapter.completed ? "Mark Unread" : "Mark Read",
                        systemImage: chapter.completed ? "circle" : "checkmark.circle")
                }
                .tint(NavigationStyle.accent)
                bookmarkButton(chapter)
                    .tint(.orange)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !selecting {
                switch chapter.downloadState {
                case .downloaded:
                    Button(role: .destructive) {
                        Task { await model.deleteDownloads([chapter.id]) }
                    } label: {
                        Label("Delete Download", systemImage: "trash")
                    }
                case .failed:
                    Button {
                        Task { await model.retryDownload(chapter.id) }
                    } label: {
                        Label("Retry Download", systemImage: "arrow.clockwise")
                    }
                    .tint(.orange)
                case .queued, .downloading:
                    Button(role: .destructive) {
                        Task { await model.cancelDownload(chapter.id) }
                    } label: {
                        Label("Cancel Download", systemImage: "xmark")
                    }
                case .none:
                    Button {
                        Task { await model.download([chapter.id]) }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .tint(NavigationStyle.accent)
                }
            }
        }
        .contextMenu { if !selecting { chapterMenu(chapter, in: filtered) } }
        .accessibilityLabel(entry.media == .anime ? "Play \(chapter.label)" : chapter.label)
        .accessibilityValue(selecting ? (isSelected ? "Selected" : "") : rowAccessibilityValue(chapter))
    }

    private func bookmarkButton(_ chapter: Chapter) -> some View {
        Button {
            Task { await model.setBookmarked([chapter.id], bookmarked: !chapter.bookmarked) }
        } label: {
            Label(
                chapter.bookmarked ? "Remove Bookmark" : "Bookmark",
                systemImage: chapter.bookmarked ? "bookmark.slash" : "bookmark")
        }
    }

    private func rowAccessibilityValue(_ chapter: Chapter) -> String {
        var parts: [String] = []
        if chapter.completed {
            parts.append("Read")
        } else if let progress = chapter.partialProgress {
            parts.append("\(Int(progress * 100))% \(entry.media == .anime ? "watched" : "read")")
        }
        if chapter.bookmarked { parts.append("Bookmarked") }
        switch chapter.downloadState {
        case .downloaded: parts.append("Downloaded")
        case .queued: parts.append("Download queued")
        case .downloading(let value): parts.append("Downloading, \(Int(value * 100))%")
        case .failed: parts.append("Download failed")
        case .none: break
        }
        return parts.joined(separator: ", ")
    }

    /// The toolbar's More menu.
    private func manageMenu(_ details: MediaDetails) -> some View {
        Menu {
            Section {
                if !details.chapters.isEmpty {
                    Button("Select Chapters", systemImage: "checkmark.circle") {
                        selecting = true
                        selected = []
                    }
                    downloadMenu(details)
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await load(refresh: true) }
                }
                .disabled(loading)
            }
            Section {
                Button("Tracking", systemImage: "antenna.radiowaves.left.and.right") { manageSheet = .tracking }
                Button("Switch Source", systemImage: "arrow.left.arrow.right") { manageSheet = .migrate }
                Button("Metadata Match", systemImage: "text.magnifyingglass") { manageSheet = .metadata }
                if isSaved {
                    Button("Automation", systemImage: "gearshape.2") { manageSheet = .automation }
                }
                Button("Cover Image", systemImage: "photo") { manageSheet = .cover }
                let links = library.linkedEntries(for: entry.id).count
                Button(links > 0 ? "Series Link (\(links))" : "Series Link", systemImage: "link") {
                    manageSheet = .link
                }
            }
            Section {
                if let browserURL = model.browserURL {
                    Button("Open in Browser", systemImage: "safari") { openURL(browserURL) }
                }
                if let sourceURL = model.sourceURL {
                    ShareLink(item: sourceURL, subject: Text(details.title)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } else {
                    ShareLink(item: details.title) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            let downloaded = details.chapters.filter(\.downloaded).map(\.id)
            if !downloaded.isEmpty {
                Button("Delete Downloads (\(downloaded.count))", systemImage: "trash", role: .destructive) {
                    Task { await model.deleteDownloads(downloaded) }
                }
            }
        } label: {
            Label("Manage", systemImage: "ellipsis.circle")
        }
        .accessibilityLabel("Manage")
        .accessibilityIdentifier("details.manage")
    }

    /// Where an unfinished chapter stopped.
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
        Button(chapter.completed ? "Mark as Unread" : "Mark as Read", systemImage: chapter.completed ? "circle" : "checkmark.circle") {
            Task { await model.setRead([chapter.id], read: !chapter.completed) }
        }
        let order = readingOrder
        if let index = order.firstIndex(where: { $0.id == chapter.id }), index > 0 {
            let previous = Set(order[..<index].map(\.id))
            Button("Mark Previous as Read", systemImage: "checkmark.circle.badge.questionmark") { Task { await model.setRead(previous, read: true) } }
            Button("Mark Previous as Unread", systemImage: "circle.dashed") { Task { await model.setRead(previous, read: false) } }
        }
        if let index = list.firstIndex(where: { $0.id == chapter.id }), index < list.count - 1 {
            let below = Set(list[(index + 1)...].map(\.id))
            Button("Mark Below as Read", systemImage: "checkmark.circle.badge.questionmark") { Task { await model.setRead(below, read: true) } }
            Button("Mark Below as Unread", systemImage: "circle.dashed") { Task { await model.setRead(below, read: false) } }
        }
        bookmarkButton(chapter)
        Divider()
        switch chapter.downloadState {
        case .downloaded:
            Button("Delete Download", systemImage: "trash", role: .destructive) { Task { await model.deleteDownloads([chapter.id]) } }
        case .failed:
            Button("Retry Download", systemImage: "arrow.clockwise") { Task { await model.retryDownload(chapter.id) } }
        case .queued, .downloading:
            Button("Cancel Download", systemImage: "xmark.circle", role: .destructive) { Task { await model.cancelDownload(chapter.id) } }
        case .none:
            Button("Download", systemImage: "arrow.down.circle") { Task { await model.download([chapter.id]) } }
        }
        if let index = order.firstIndex(where: { $0.id == chapter.id }) {
            let rest = order[index...].filter(\.canQueueDownload).map(\.id)
            if rest.count > 1 {
                Button("Download Next 5 from Here", systemImage: "arrow.down.to.line") { Task { await model.download(Array(rest.prefix(5))) } }
                Button("Download All from Here", systemImage: "arrow.down.to.line.compact") { Task { await model.download(rest) } }
            }
        }
        Divider()
        Button("Select", systemImage: "checkmark.circle") {
            selecting = true
            selected = [chapter.id]
        }
    }

    private func downloadMenu(_ details: MediaDetails) -> some View {
        let order = readingOrder
        let start = model.continueTarget(preferences: chapterPreferences)?.chapter.id
        let fromIndex = order.firstIndex { $0.id == start } ?? 0
        let ahead = order[fromIndex...].filter(\.canQueueDownload).map(\.id)
        let unread = order.filter { !$0.completed && $0.canQueueDownload }.map(\.id)
        let missing = order.filter(\.canQueueDownload).map(\.id)
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
            Button("Custom Range…") { manageSheet = .downloadRange }.disabled(missing.isEmpty)
            if !downloaded.isEmpty {
                Button("Delete all downloads (\(downloaded.count))", role: .destructive) {
                    Task { await model.deleteDownloads(downloaded) }
                }
            }
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
        .accessibilityLabel("Download chapters")
        .accessibilityIdentifier("details.downloadMenu")
    }

    private var selectionBar: some View {
        let ids = selected
        let chosen = (details?.chapters ?? []).filter { ids.contains($0.id) }
        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 4) {
                Button(selected.count == filteredChapters.count ? "Select None" : "Select All") {
                    selected = selected.count == filteredChapters.count ? [] : Set(filteredChapters.map(\.id))
                }
                .frame(minHeight: 44)
                Text("\(selected.count) selected").font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                Group {
                    barButton("Mark read", icon: "checkmark.circle") { await model.setRead(ids, read: true) }
                    barButton("Mark unread", icon: "circle") { await model.setRead(ids, read: false) }
                    // Bookmarks all unless every selected chapter already has one.
                    let unbookmark = !chosen.isEmpty && chosen.allSatisfy(\.bookmarked)
                    barButton(unbookmark ? "Remove bookmarks" : "Bookmark",
                              icon: unbookmark ? "bookmark.slash" : "bookmark") {
                        await model.setBookmarked(ids, bookmarked: !unbookmark)
                    }
                    barButton("Download", icon: "arrow.down.circle") {
                        await model.download(chosen.filter(\.canQueueDownload).map(\.id))
                    }
                    barButton("Delete downloads", icon: "trash") {
                        await model.deleteDownloads(chosen.filter(\.downloaded).map(\.id))
                    }
                }
                .disabled(selected.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
        }
        .background(.bar)
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
            Image(systemName: icon).font(.title3).frame(width: 44, height: 44)
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
                Label("Scanlators", systemImage: "line.3.horizontal.decrease.circle").font(.subheadline).frame(minHeight: 44)
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

/// Wraps chips onto as many rows as they need.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in rows.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], width: CGFloat, height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            // A chip longer than the row wraps its own text instead of overflowing.
            if size.width > width { size = view.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if x > 0, x + size.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return (frames, widest, y + row)
    }
}

extension EnvironmentValues {
    /// Shows Close when Details is the root of a sheet or cover; pushed pages use the system back button.
    @Entry var detailsShowsClose = false
    /// Opens Search filtered by a genre; nil where no search is reachable.
    @Entry var searchGenre: (@MainActor (String) -> Void)? = nil
}

/// Trailing download state on a chapter row: queued, a progress ring, failed, or done.
struct ChapterDownloadIndicator: View {
    let state: Chapter.DownloadState
    @ScaledMetric(relativeTo: .body) private var ring: CGFloat = 17

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .downloaded:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(NavigationStyle.accent)
                .accessibilityLabel("Downloaded")
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Download queued")
        case .downloading(let value):
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 2.5)
                Circle().trim(from: 0, to: max(0.03, value))
                    .stroke(NavigationStyle.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: value)
            }
            .frame(width: ring, height: ring)
            .accessibilityElement()
            .accessibilityLabel("Downloading")
            .accessibilityValue("\(Int(value * 100))%")
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Download failed")
        }
    }
}

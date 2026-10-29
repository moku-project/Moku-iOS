import SwiftUI

/// Native counterpart of desktop SeriesHeader + ChapterList.
struct DetailsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ReaderPreferences.self) private var readerPreferences
    @AppStorage("library.autoLinkOnOpen") private var autoLinkOnOpen = false
    @State private var linkedEntry: MediaEntry?
    @State private var readingChapter: Chapter?
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
    }
    @AppStorage("chapter.displayPreferences") private var chapterPreferences = Data()
    @State private var playingChapter: Chapter?

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
                    metadata.frame(maxWidth: geometry.size.width >= 700 ? 240 : .infinity)
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
                               query: chapterQuery, ascending: ascending)) {
            let result = await ChapterPresentation.filtered(
                details?.chapters ?? [], preferences: chapterPreferences, mediaID: entry.id,
                query: chapterQuery, ascending: ascending)
            guard !Task.isCancelled else { return }
            filteredChapters = result
        }
        .sheet(item: $linkedEntry) { linked in
            DetailsView(entry: linked) { linkedEntry = nil }
        }
        .fullScreenCover(item: $playingChapter) { chapter in
            if let details {
                PlayerView(
                    model: PlayerViewModel(
                        title: details.title, mediaID: details.id,
                        chapters: details.chapters, chapterID: chapter.id))
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
                    onClose: { readingChapter = nil })
            }
        }
        .fullScreenCover(
            item: Binding(
                get: { readerPreferences.document.behaviour.containerized ? nil : readingChapter },
                set: {
                    if !readerPreferences.document.behaviour.containerized { readingChapter = $0 }
                })
        ) { chapter in
            if let details {
                ReaderView(
                    details: details, chapterID: chapter.id, preferences: readerPreferences)
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 14) {
            CoverImage(
                url: details.flatMap { BackendAPI.coverURL($0.thumbnailUrl) } ?? entry.coverURL,
                symbol: entry.media.symbol
            )
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(details?.title ?? entry.title).font(.headline)
            if loading && details == nil {
                ContentSkeleton(style: .settings, count: 3)
            }
            if let byline = details?.byline, !byline.isEmpty {
                Text(byline).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if let status = details?.status {
                    badge(status.capitalized, accent: true)
                }
                badge(entry.sourceName)
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
                Button {
                    Task { await toggleLibrary() }
                } label: {
                    Label(
                        library.contains(entry) ? "In Library" : "Add to Library",
                        phosphor: library.contains(entry) ? "Bookmark.fill" : "Bookmark"
                    )
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 6))
                }
                .disabled(saving)
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
                Button {
                    ascending.toggle()
                } label: {
                    PhosphorIcon(ascending ? "ArrowUp" : "ArrowDown")
                        .frame(width: 44, height: 44)
                }.accessibilityLabel("Reverse chapter order")
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
                            if entry.media == .manga {
                                readingChapter = chapter
                            } else if entry.media == .anime {
                                playingChapter = chapter
                            }
                        } label: {
                            HStack(spacing: 12) {
                                PhosphorIcon(
                                    chapter.completed ? "Circle.fill" : "Circle"
                                )
                                .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chapter.label).font(.subheadline)
                                    if let scanlator = chapter.scanlator {
                                        Text(scanlator).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if chapter.downloaded {
                                    PhosphorIcon("DownloadSimple.fill").foregroundStyle(
                                        NavigationStyle.accent)
                                }
                            }.padding(.vertical, 14).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button(chapter.downloaded ? "Delete download" : "Download") {
                                Task {
                                    guard let details = model.details else { return }
                                    do {
                                        if chapter.downloaded {
                                            let _: [String: Bool] = try await BackendAPI.shared.graphql("mutation { deleteDownload(mediaId: \(BackendAPI.literal(details.id)), chapterIds: [\(BackendAPI.literal(chapter.id))]) }", requiresSourceRuntime: false)
                                        } else {
                                            struct Queued: Decodable, Sendable { struct Item: Decodable, Sendable { let id: String }; let enqueueDownload: [Item] }
                                            let _: Queued = try await BackendAPI.shared.graphql("mutation { enqueueDownload(mediaId: \(BackendAPI.literal(details.id)), chapterIds: [\(BackendAPI.literal(chapter.id))]) { id } }", requiresSourceRuntime: false)
                                        }
                                        await model.load()
                                    } catch { model.chapterError = "Couldn’t update this download. Try again." }
                                }
                            }
                        }

                            .disabled(entry.media != .anime && entry.media != .manga)
                            .accessibilityLabel(
                                entry.media == .anime ? "Play \(chapter.label)" : chapter.label)
                        Divider()
                    }
                }
            }
        }
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
                if entry.media == .manga {
                    readingChapter = chapter
                } else if entry.media == .anime {
                    playingChapter = chapter
                } else {
                    model.error = "The novel reader is not available yet."
                }
            } else {
                model.error =
                    "This chapter is no longer available. You can choose another chapter below."
            }
        }
    }

    private func toggleLibrary() async {
        saving = true
        defer { saving = false }
        if !(await library.setSaved(!library.contains(entry), entry: entry)) {
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

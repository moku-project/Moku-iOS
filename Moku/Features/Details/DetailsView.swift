import SwiftUI

/// Native counterpart of desktop SeriesHeader + ChapterList.
struct DetailsView: View {
    @Environment(ProfileLibrary.self) private var library
    @Environment(ReaderPreferences.self) private var readerPreferences
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
        .firstLoadSkeleton("details-\(entry.id)", loading: loading, style: .results)
        .background(NavigationStyle.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            BackHeader(title: "Details", backLabel: "Back", identifier: "details.back", back: back)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: entry.id) {
            ascending = defaultAscending
            await library.load()
            await load()
        }
        .fullScreenCover(item: $playingChapter) { chapter in
            if let details {
                PlayerView(
                    model: PlayerViewModel(
                        title: details.title, mediaID: details.id,
                        chapters: details.chapters, chapterID: chapter.id))
            }
        }
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
                    let read = details.chapters.filter(\.completed).count
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
                let filtered = details.chapters.filter {
                    chapterQuery.isEmpty || $0.label.localizedCaseInsensitiveContains(chapterQuery)
                }.sorted {
                    ascending
                        ? ($0.number ?? 0) < ($1.number ?? 0) : ($0.number ?? 0) > ($1.number ?? 0)
                }
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

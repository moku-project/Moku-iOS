import SwiftUI
import Observation

struct HomeView: View {
    let store: HomeStore
    var onResume: ((HomeEntry, HomeChapter) -> Void)?
    var isActive = true
    var onOpenLibrary: () -> Void = {}
    var onGenre: (String) -> Void = { _ in }
    var onOpenLibraryTitle: ((MediaEntry) -> Void)?
    var onOpenTitle: ((MediaEntry, String?) -> Void)?
    @Environment(LibraryStore.self) private var library: LibraryStore?
    @Environment(ReaderPreferences.self) private var readerPreferences: ReaderPreferences?
    @State private var loader = HomeTitleLoader()
    @AppStorage("chapter.displayPreferences") private var chapterPreferences = Data()
    @State private var route: HomeRoute?
    @State private var opening = false
    @State private var openError: String?
    @State private var pinQuery = ""
    @State private var libraryBreakdown: [String: Int]?
    @State private var activityStatistics = HomeStatistics()
    @State private var preparedChapters: [HomeChapter]?
    @State private var preparedEntryID: String?

    private struct ChapterPreparation: Hashable {
        let revision: Int
        let entryID: String?
        let preferences: Data
    }

    private struct HomeRoute: Identifiable {
        let entry: MediaEntry
        var chapterID: String?
        var id: String { entry.id + (chapterID ?? "") }
    }
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("preferences.animations") private var animations = true
    private var reduceMotion: Bool { systemReduceMotion || !animations }
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var lastInteraction = Date()
    @State private var expandedDescriptions: Set<Int> = []
    @State private var pageScrolling = false
    @GestureState private var heroDragging = false
    @State private var heroVisible = false
    @State private var activeSlot = 0
    @State private var heroHeights: [Int: CGFloat] = [:]
    @State private var presentation: HomePresentation?

    private enum HomePresentation: Identifiable {
        case history
        case pin(Int)
        var id: String {
            switch self {
            case .history: "history"
            case .pin(let slot): "pin-\(slot)"
            }
        }
    }

    private var carouselSlots: [HomeSlot] {
        let populated = store.slots.filter { $0.entry != nil }
        return populated.isEmpty ? [HomeSlot(id: 0)] : populated
    }
    private var carouselIDs: [Int] { carouselSlots.map(\.id) }
    private var autoRotates: Bool {
        isActive && store.isLoaded && heroVisible && scenePhase == .active
            && carouselSlots.count > 1 && !expandedDescriptions.contains(activeSlot) && !pageScrolling && !heroDragging
            && !reduceMotion && !voiceOver && !opening && route == nil
            && presentation == nil && openError == nil
    }

    private var slot: HomeSlot {
        var value = store.slots[activeSlot]
        if let entry = value.entry, preparedEntryID == entry.id, let preparedChapters {
            value.entry?.chapters = preparedChapters
        }
        return value
    }
    private var statistics: HomeStatistics {
        var value = activityStatistics
        if let libraryBreakdown { value.byMedia = libraryBreakdown }
        return value
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !store.isLoaded {
                    ContentSkeleton(style: .home)
                } else {
                    carousel
                    upcoming
                    recent
                    HomeActivityView(statistics: statistics)
                }
                if let error = store.storageError {
                    Label(error, phosphor: "Warning")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, NavigationStyle.pagePadding)
            .padding(.bottom, 8)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .firstLoadSkeleton("home", loading: !store.isLoaded, style: .home)
        .accessibilityIdentifier("home.scroll")
        .tracksNavigationScroll()
        .onScrollPhaseChange { _, phase in pageScrolling = phase != .idle }
        .onChange(of: carouselIDs, initial: true) { _, ids in
            if !ids.contains(activeSlot) { activeSlot = ids.first ?? 0 }
        }
        .simultaneousGesture(TapGesture().onEnded { lastInteraction = .now })
        .simultaneousGesture(DragGesture().updating($heroDragging) { _, dragging, _ in
            dragging = true
        }.onEnded { _ in lastInteraction = .now })
        .task(id: "\(autoRotates)-\(activeSlot)-\(carouselIDs)-\(lastInteraction.timeIntervalSinceReferenceDate)") {
            guard autoRotates else { return }
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard !Task.isCancelled, autoRotates else { return }
            changeSlot(1)
        }
        .navigationTitle("Home")
        .alert("Couldn’t open title", isPresented: Binding(
            get: { openError != nil }, set: { if !$0 { openError = nil } }
        )) {
            Button("OK") { openError = nil }
        } message: { Text(openError ?? "") }
        .task { await store.load(); await library?.load() }
        .task(id: "\(isActive)-\(store.snapshotRevision)") {
            guard isActive else { return }
            let snapshot = store.snapshot
            let result = await Task.detached(priority: .userInitiated) {
                HomeStatistics.calculate(snapshot: snapshot)
            }.value
            guard !Task.isCancelled else { return }
            activityStatistics = result
        }
        .task(id: "\(isActive)-\(store.slots[activeSlot].entry?.id ?? "empty")") {
            if isActive { await refreshHero() }
        }
        .task(id: ChapterPreparation(
            revision: loader.chapterRevision, entryID: loader.entryID, preferences: chapterPreferences
        )) {
            guard let entryID = loader.entryID, let chapters = loader.chapters else {
                preparedChapters = nil
                preparedEntryID = nil
                return
            }
            let preferences = chapterPreferences
            let prepared = await Task.detached(priority: .userInitiated) {
                ChapterDisplayPreferences.read(preferences, id: entryID).apply(chapters).map {
                    HomeChapter(id: $0.id, title: $0.label, isRead: $0.completed, uploadedAt: $0.uploadedAt)
                }
            }.value
            guard !Task.isCancelled else { return }
            preparedEntryID = entryID
            preparedChapters = prepared
        }
        .refreshable { await refreshHero(refresh: true); await refreshBreakdown() }
        .task(id: "\(isActive)-\(library?.entriesRevision ?? 0)-\(store.snapshotRevision)") {
            if isActive { await refreshBreakdown() }
        }
        .fullScreenCover(item: $route, onDismiss: { Task { await refreshHero(refresh: true); await refreshBreakdown() } }) { route in
            NavigationStack {
                DetailsView(entry: route.entry, initialChapterID: route.chapterID) { self.route = nil }
            }
        }
        .sheet(item: $presentation) { page in
            switch page {
            case .history:
                historySheet
            case .pin(let slot):
                pinSheet(slot: slot)
            }
        }
    }

    private var historySheet: some View {
        NavigationStack {
            RecentView(mode: .constant(.all))
                .safeAreaInset(edge: .top) {
                    HStack {
                        Text("History").font(.headline)
                        Spacer()
                        Button("Done") { presentation = nil }
                    }.padding()
                }
        }.preferredColorScheme(.dark)
    }

    private func pinSheet(slot: Int) -> some View {
        NavigationStack {
            List {
                ForEach((library?.entries ?? []).filter {
                    pinQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(pinQuery)
                }) { entry in
                    Button {
                        store.pin(HomeEntry(entry), slot: slot)
                        presentation = nil
                    } label: {
                        HStack(spacing: 12) {
                            HomeCover(url: entry.coverURL).frame(width: 36, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title).foregroundStyle(.primary)
                                Text(entry.sourceName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $pinQuery, prompt: "Search library")
            .overlay {
                if library?.entries.isEmpty != false {
                    ContentUnavailableView("Your library is empty", phosphor: "Books")
                } else if !(library?.entries.contains {
                    pinQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(pinQuery)
                } ?? false) {
                    ContentUnavailableView.search(text: pinQuery)
                }
            }
            .task { await library?.load() }
            .navigationTitle("Pin a title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentation = nil }
                }
            }
        }.preferredColorScheme(.dark)
    }

    private func refreshBreakdown() async {
        guard let library else { return }
        await library.load()
        do {
            let breakdown = try await HomeTitleLoader.libraryCounts(library.entries)
            try Task.checkCancellation()
            libraryBreakdown = breakdown
        } catch {
            // Keep the last successful library summary while offline.
        }
    }

    private func refreshHero(refresh: Bool = false) async {
        guard let entry = store.slots[activeSlot].entry else { return }
        await library?.load()
        await loader.load(entry, library: library?.entries ?? [], refresh: refresh)
        if !Task.isCancelled, let updated = loader.updatedEntry, updated.id == entry.id {
            store.updateEntry(updated)
        }
    }

    private func resume(_ entry: HomeEntry, _ chapter: HomeChapter) {
        if let onResume { onResume(entry, chapter) }
        else { open(entry, chapterID: chapter.id) }
    }

    private func open(_ entry: HomeEntry, chapterID: String? = nil, inLibrary: Bool = false) {
        guard !opening else { return }
        opening = true
        openError = nil
        Task {
            defer { opening = false }
            do {
                let media = try await loader.resolve(entry, library: library?.entries ?? [])
                if media.media == .manga, let chapterID,
                   let session = store.snapshot.sessions.filter({
                       $0.entryID == entry.id && $0.chapterID == chapterID
                   }).max(by: { $0.endedAt < $1.endedAt }) {
                    readerPreferences?.document.positions[media.id] = ReaderPosition(
                        chapterID: chapterID, page: max(1, session.page))
                }
                if inLibrary, let onOpenLibraryTitle { onOpenLibraryTitle(media) }
                else if let onOpenTitle { onOpenTitle(media, chapterID) }
                else { route = HomeRoute(entry: media, chapterID: chapterID) }
            } catch {
                openError = "Couldn’t open this title. Check its source and try again."
            }
        }
    }

    private var carousel: some View {
        VStack(spacing: 4) {
            TabView(selection: $activeSlot) {
                ForEach(carouselSlots) { item in
                    HomeHeroCard(
                        slot: item, onResume: resume, onDetails: { open($0) },
                        onLibrary: { open($0, inLibrary: true) },
                        onPin: { pinQuery = ""; presentation = .pin(item.id) },
                        onUnpin: { store.pin(nil, slot: item.id) }, onGenre: onGenre, isOpening: opening,
                        onHeightChange: { heroHeights[item.id] = $0 },
                        onExpansionChange: { expanded in
                            if expanded { expandedDescriptions.insert(item.id) }
                            else { expandedDescriptions.remove(item.id) }
                            lastInteraction = .now
                        }
                    )
                    .tag(item.id)
                    .contextMenu {
                        if item.id > 0 {
                            Button("Pin a title", phosphor: "PushPin") {
                                pinQuery = ""; presentation = .pin(item.id)
                            }
                            if item.isPinned {
                                Button("Unpin", phosphor: "PushPinSlash") {
                                    store.pin(nil, slot: item.id)
                                }
                            }
                        }
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: heroHeights[activeSlot] ?? (typeSize.isAccessibilitySize ? 510 : 230))
            .accessibilityIdentifier("home.carousel")
            .accessibilityValue("Title \((carouselIDs.firstIndex(of: activeSlot) ?? 0) + 1) of \(carouselIDs.count)")
            .onScrollVisibilityChange(threshold: 0.5) { heroVisible = $0 }
            .accessibilityAdjustableAction { direction in
                lastInteraction = .now
                changeSlot(direction == .increment ? 1 : -1)
            }
            CarouselBreadcrumbs(
                count: carouselIDs.count,
                selection: carouselIDs.firstIndex(of: activeSlot) ?? 0,
                accessibilityPrefix: "home"
            ) { index in
                lastInteraction = .now
                setSlot(carouselIDs[index])
            }
        }
    }

    private var upcoming: some View {
        // Resolve chapter preferences once, outside the chapter search and row closures.
        // Re-reading the computed property in firstIndex rebuilds the full list per chapter.
        let slot = self.slot
        return VStack(spacing: 12) {
            HStack {
                Text("Up next").font(.headline)
                Spacer(minLength: 12)
                if let entry = slot.entry, loader.entryID == entry.id, let chapters = loader.chapters {
                    ChapterScanlatorMenu(chapters: chapters, mediaID: entry.id)
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44)
                }
                if let entry = slot.entry {
                    Button("All chapters") { open(entry) }
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                }
            }
            .frame(minHeight: 44)
            if loader.loading && (slot.entry?.chapters.isEmpty ?? true) {
                ContentSkeleton(style: .chapters, count: 3)
            }
            if let error = loader.error, loader.entryID == slot.entry?.id {
                HStack {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { Task { await refreshHero(refresh: true) } }
                }
            }
            if let entry = slot.entry, !entry.chapters.isEmpty {
                let currentIndex =
                    entry.chapters.firstIndex { $0.id == slot.session?.chapterID }
                    ?? entry.chapters.lastIndex(where: \.isRead) ?? 0
                VStack(spacing: 4) {
                    ForEach(Array(entry.chapters.dropFirst(currentIndex).prefix(5))) { chapter in
                        Button {
                            resume(entry, chapter)
                        } label: {
                            HomeChapterRow(
                                chapter: chapter, current: chapter.id == slot.session?.chapterID,
                                page: slot.session?.page, isAnime: entry.media == "Anime")
                        }.buttonStyle(.plain)
                    }
                }
            } else {
                HomeEmptyRow(text: "No chapters to show", symbol: "ListBullets")
            }
        }
    }

    private var recent: some View {
        VStack(spacing: 12) {
            HomeSectionHeading(
                title: "Recent activity", action: store.recentSessions.isEmpty ? nil : "History",
                perform: { presentation = .history })
            if store.recentSessions.isEmpty {
                HomeEmptyRow(text: "No recent activity yet", symbol: "Clock")
                Button("Start reading", action: onOpenLibrary)
                    .frame(minHeight: 44).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.recentSessions.prefix(5))) { session in
                        if let entry = store.entry(session.entryID) {
                            Button {
                                open(entry, chapterID: session.chapterID)
                            } label: {
                                HomeRecentRow(entry: entry, session: session)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(.white.opacity(0.04))
                        }
                    }
                }
            }
        }
    }

    private func changeSlot(_ offset: Int) {
        let ids = carouselIDs
        guard ids.count > 1 else { return }
        let position = ids.firstIndex(of: activeSlot) ?? 0
        setSlot(ids[(position + offset + ids.count) % ids.count])
    }
    private func setSlot(_ index: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { activeSlot = index }
    }
}

/// Loads one selected title; cancelled carousel requests cannot replace a newer slot.
@MainActor @Observable
final class HomeTitleLoader {
    var entryID: String?
    var updatedEntry: HomeEntry?
    var chapters: [Chapter]? { didSet { chapterRevision &+= 1 } }
    private(set) var chapterRevision = 0
    var loading = false
    var error: String?
    private var generation = UUID()
    private let repository: any DetailsRepository
    init(repository: any DetailsRepository = AppDependencies.detailsRepository) {
        self.repository = repository
    }

    static func libraryCounts(_ entries: [MediaEntry]) async throws -> [String: Int] {
        struct Counts: Decodable, Sendable { let chapterCount: Int; let unreadCount: Int }
        var result: [String: Int] = [:]
        for offset in stride(from: 0, to: entries.count, by: 40) {
            let batch = Array(entries.dropFirst(offset).prefix(40))
            let fields = batch.enumerated().map { index, entry in
                "m\(index): media(id: \(BackendAPI.literal(entry.id))) { chapterCount unreadCount }"
            }.joined(separator: " ")
            let response: [String: Counts?] = try await BackendAPI.shared.graphql(
                "{ \(fields) }", cacheFor: 30, requiresSourceRuntime: false)
            for (index, entry) in batch.enumerated() {
                if let counts = response["m\(index)"] ?? nil {
                    result[entry.media.title, default: 0] += max(0, counts.chapterCount - counts.unreadCount)
                }
            }
        }
        return result
    }

    func resolve(_ entry: HomeEntry, library: [MediaEntry]) async throws -> MediaEntry {
        if let saved = library.first(where: { $0.id == entry.id }) { return saved }
        if let saved = entry.sourceEntry { return saved }
        return try await LiveRecentRepository().entry(id: entry.id)
    }

    func load(_ entry: HomeEntry, library: [MediaEntry], refresh: Bool) async {
        let token = UUID()
        generation = token
        if entryID != entry.id { chapters = nil }
        entryID = entry.id
        updatedEntry = nil
        error = nil
        loading = true
        defer { if generation == token { loading = false } }
        do {
            let media = try await resolve(entry, library: library)
            let details = try await repository.metadata(for: media, refresh: refresh)
            try Task.checkCancellation()
            guard generation == token else { return }
            var next = entry
            next.title = details.title
            next.coverURL = BackendAPI.coverURL(details.thumbnailUrl) ?? media.coverURL
            next.sourceEntry = media
            next.author = details.byline
            next.summary = details.description
            next.genres = details.genres
            updatedEntry = next
            let chapters = try await repository.chapters(mediaID: details.id, refresh: refresh)
            try Task.checkCancellation()
            guard generation == token else { return }
            next.unreadCount = chapters.filter { !$0.completed }.count
            self.chapters = chapters
            next.chapters = ChapterDisplayPreferences().apply(chapters).map {
                HomeChapter(id: $0.id, title: $0.label, isRead: $0.completed, uploadedAt: $0.uploadedAt)
            }
            updatedEntry = next
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            self.error = "Couldn’t refresh chapters."
        }
    }
}

import SwiftUI
import Observation

/// Continue card, stats, activity, up next and recent, in the Android order.
struct HomeView: View {
    let store: ReadingHistory
    var isActive = true
    var onBrowse: () -> Void = {}
    var onOpenTitle: ((MediaEntry, String?) -> Void)?
    @Environment(LibraryStore.self) private var library: LibraryStore?
    @State private var loader = HomeTitleLoader()
    @State private var route: HomeRoute?
    @State private var opening = false
    @State private var openError: String?
    @State private var featuredResume: ResumePoint?

    private static let weeks = 18

    private struct HomeRoute: Identifiable {
        let entry: MediaEntry
        var chapterID: String?
        var id: String { entry.id + (chapterID ?? "") }
    }

    private var items: [HomeItem] {
        store.recent.map { HomeItem(entry: store.entry(for: $0), session: $0) }
    }
    /// The next most recent title that still has something unread.
    private func upNext(_ items: [HomeItem]) -> HomeItem? {
        items.dropFirst().first { $0.entry.unreadCount > 0 }
    }

    var body: some View {
        let items = self.items
        let upNext = upNext(items)
        let recent = Array(items.dropFirst().filter { $0.id != upNext?.id }.prefix(5))
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !store.isLoaded {
                    ContentSkeleton(style: .home)
                } else {
                    if let featured = items.first {
                        HomeContinueCard(
                            item: featured, opening: opening,
                            resume: { open(featured.entry, chapterID: resumeChapter(featured)) },
                            details: { open(featured.entry) })
                    } else {
                        HomeWelcomeCard(browse: onBrowse)
                    }
                    HomeSection(title: "Your Stats", systemImage: "chart.line.uptrend.xyaxis") {
                        HomeStatsStrip(statistics: store.statistics)
                    }
                    HomeSection(
                        title: "Activity", systemImage: "clock",
                        trailing: "\(HomeHeatmap.total(store.statistics.daily, weeks: Self.weeks)) in \(Self.weeks) weeks"
                    ) {
                        HomeHeatmap(daily: store.statistics.daily, weeks: Self.weeks)
                    }
                    HomeSection(title: "Up Next") {
                        Group {
                            if let upNext {
                                HomeMediaRow(item: upNext) { open(upNext.entry, chapterID: upNext.session.endChapterID) }
                            } else {
                                HStack {
                                    Text("Nothing queued yet").font(.subheadline).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Find Something", action: onBrowse)
                                        .font(.subheadline.weight(.medium)).buttonStyle(.bordered)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .homeCard(padding: EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("home.upNext")
                    }
                    if !recent.isEmpty {
                        HomeSection(title: "Recent") {
                            VStack(spacing: 0) {
                                ForEach(recent) { item in
                                    if item.id != recent.first?.id { Divider() }
                                    HomeMediaRow(item: item) { open(item.entry, chapterID: item.session.endChapterID) }
                                        .contextMenu {
                                            Button("Resume", systemImage: "play.fill") {
                                                open(item.entry, chapterID: item.session.endChapterID)
                                            }
                                            Button("View Title", systemImage: "info.circle") { open(item.entry) }
                                        }
                                }
                            }
                            .homeCard(padding: EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("home.recent")
                        }
                    }
                }
                if let error = store.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .firstLoadSkeleton("home", loading: !store.isLoaded, style: .home)
        .accessibilityIdentifier("home.scroll")
        .navigationTitle("Home")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Search", systemImage: "magnifyingglass", action: onBrowse)
                    .accessibilityIdentifier("home.search")
                NavigationLink(value: Route.more(.extensions)) {
                    Label("Extensions", systemImage: "puzzlepiece.extension")
                }
                .accessibilityIdentifier("home.extensions")
            }
        }
        .alert("Couldn’t open title", isPresented: Binding(
            get: { openError != nil }, set: { if !$0 { openError = nil } }
        )) {
            Button("OK") { openError = nil }
        } message: { Text(openError ?? "") }
        .task { await store.load(); await library?.load() }
        .task(id: "\(isActive)-\(items.first?.id ?? "empty")") {
            if isActive { await refreshFeatured() }
        }
        .refreshable { await store.refresh(); await refreshFeatured(refresh: true) }
        .fullScreenCover(item: $route, onDismiss: { Task { await refreshFeatured(refresh: true) } }) { route in
            NavigationStack {
                DetailsView(entry: route.entry, initialChapterID: route.chapterID) { self.route = nil }
                    .environment(\.detailsShowsClose, true)
            }
        }
    }

    private func refreshFeatured(refresh: Bool = false) async {
        guard let entry = items.first?.entry else { return }
        await library?.load()
        async let resume = try? store.repository.resumePoint(mediaID: entry.id)
        await loader.load(entry, library: library?.entries ?? [], refresh: refresh)
        if !Task.isCancelled, let updated = loader.updatedEntry, updated.id == entry.id {
            store.update(updated)
        }
        let point = await resume
        if !Task.isCancelled, items.first?.id == entry.id { featuredResume = point ?? nil }
    }

    /// The resume point is synced from every device; the session is the fallback until it loads.
    private func resumeChapter(_ item: HomeItem) -> String? {
        featuredResume.map(\.chapterID) ?? item.session.endChapterID
    }

    private func open(_ entry: HomeEntry, chapterID: String? = nil) {
        guard !opening else { return }
        opening = true
        openError = nil
        Task {
            defer { opening = false }
            do {
                let media = try await loader.resolve(entry, library: library?.entries ?? [])
                if let onOpenTitle { onOpenTitle(media, chapterID) }
                else { route = HomeRoute(entry: media, chapterID: chapterID) }
            } catch {
                openError = "Couldn’t open this title. Check its source and try again."
            }
        }
    }
}

/// Refreshes one title's metadata and chapters; a newer load supersedes an older one.
@MainActor @Observable
final class HomeTitleLoader {
    private(set) var updatedEntry: HomeEntry?
    private var generation = UUID()
    private let repository: any DetailsRepository
    init(repository: any DetailsRepository = AppDependencies.detailsRepository) {
        self.repository = repository
    }

    func resolve(_ entry: HomeEntry, library: [MediaEntry]) async throws -> MediaEntry {
        if let saved = library.first(where: { $0.id == entry.id }) { return saved }
        if let saved = entry.sourceEntry { return saved }
        return try await LiveRecentRepository().entry(id: entry.id)
    }

    func load(_ entry: HomeEntry, library: [MediaEntry], refresh: Bool) async {
        let token = UUID()
        generation = token
        updatedEntry = nil
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
            next.chapters = ChapterDisplayPreferences().apply(chapters).map {
                HomeChapter(id: $0.id, title: $0.label, isRead: $0.completed, uploadedAt: $0.uploadedAt)
            }
            updatedEntry = next
        } catch {
            // Home keeps the saved title when its source can't be reached.
        }
    }
}

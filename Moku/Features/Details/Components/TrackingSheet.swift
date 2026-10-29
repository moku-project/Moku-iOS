import SwiftUI

/// Desktop TrackerPanel: link a title to each signed-in tracker, then edit
/// status, progress and score, pull from the tracker, or unlink.
struct TrackingSheet: View {
    let mediaID: String
    let title: String
    let isAnime: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var trackers: [Tracker] = []
    @State private var links: [TrackLink] = []
    @State private var loading = true
    @State private var error: String?
    @State private var searchingTracker: String?
    @State private var query = ""
    @State private var results: [TrackResult] = []
    @State private var searching = false

    struct Tracker: Decodable, Identifiable, Sendable {
        struct Status: Decodable, Sendable { let value: Int; let name: String; let animeName: String }
        let key: String
        let name: String
        let isLoggedIn: Bool
        let scoreOptions: [String]
        let statusOptions: [Status]
        var id: String { key }
    }

    struct TrackLink: Decodable, Identifiable, Sendable {
        let id: String
        let trackerKey: String
        let title: String
        let url: String
        let status: Int
        let lastChapterRead: Double
        let totalChapters: Int
        let score: Double
    }

    struct TrackResult: Decodable, Identifiable, Sendable {
        let remoteId: String
        let title: String
        let coverUrl: String?
        let totalChapters: Int?
        let publishingStatus: String?
        var id: String { remoteId }
    }

    private static let linkFields = "id trackerKey title url status lastChapterRead totalChapters score"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if loading {
                        ContentSkeleton(style: .settings, count: 3)
                    } else if trackers.filter(\.isLoggedIn).isEmpty {
                        Text("No tracker is connected. Sign in to AniList in More → Tracking, then come back to link this title.")
                            .font(.subheadline).foregroundStyle(GeneralStyle.label)
                    }
                    ForEach(trackers.filter(\.isLoggedIn)) { tracker in
                        section(tracker)
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                    }
                }
                .padding(20)
            }
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle("Tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }

    @ViewBuilder private func section(_ tracker: Tracker) -> some View {
        GeneralSection(tracker.name) {
            if let link = links.first(where: { $0.trackerKey == tracker.key }) {
                linked(link, tracker: tracker)
            } else if searchingTracker == tracker.key {
                search(tracker)
            } else {
                GeneralRow("Not linked", detail: "Find this title on \(tracker.name) to sync your progress.") {
                    Button("Link") {
                        searchingTracker = tracker.key
                        query = title
                        Task { await runSearch(tracker) }
                    }
                    .buttonStyle(GeneralTextButtonStyle())
                }
            }
        }
    }

    private func linked(_ link: TrackLink, tracker: Tracker) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GeneralRow(link.title, detail: "Now tracking") {
                if let url = URL(string: link.url) {
                    Link(destination: url) { PhosphorIcon("ArrowUpRight", size: 14) }
                        .accessibilityLabel("Open on \(tracker.name)")
                }
            }
            GeneralStyle.divider
            GeneralRow("Status", detail: "") {
                Menu {
                    ForEach(tracker.statusOptions, id: \.value) { option in
                        Button(isAnime ? option.animeName : option.name) {
                            Task { await update(link, status: option.value) }
                        }
                    }
                } label: {
                    let current = tracker.statusOptions.first { $0.value == link.status }
                    Text(current.map { isAnime ? $0.animeName : $0.name } ?? "Choose")
                        .font(.subheadline).foregroundStyle(NavigationStyle.accent)
                }
            }
            GeneralStyle.divider
            GeneralRow(isAnime ? "Episodes watched" : "Chapters read",
                       detail: link.totalChapters > 0 ? "of \(link.totalChapters)" : "") {
                Stepper(
                    value: Binding(
                        get: { link.lastChapterRead },
                        set: { value in Task { await update(link, progress: value) } }),
                    in: 0...Double(max(link.totalChapters, 10_000)), step: 1
                ) {
                    Text(link.lastChapterRead.formatted()).monospacedDigit()
                }
                .fixedSize()
            }
            if !tracker.scoreOptions.isEmpty {
                GeneralStyle.divider
                GeneralRow("Score", detail: "") {
                    Menu {
                        ForEach(tracker.scoreOptions, id: \.self) { option in
                            Button(option) { Task { await update(link, score: Double(option) ?? 0) } }
                        }
                    } label: {
                        Text(link.score == 0 ? "No score" : link.score.formatted())
                            .font(.subheadline).foregroundStyle(NavigationStyle.accent)
                    }
                }
            }
            GeneralStyle.divider
            HStack {
                Button("Sync from \(tracker.name)") { Task { await mutate("resyncTrack(linkId: \(BackendAPI.literal(link.id))) { \(Self.linkFields) }") } }
                Spacer()
                Button("Unlink", role: .destructive) {
                    Task {
                        let _: IgnoredGraphQLResult? = try? await BackendAPI.shared.graphql(
                            "mutation { unbindTrack(linkId: \(BackendAPI.literal(link.id))) }", requiresSourceRuntime: false)
                        await load()
                    }
                }
            }
            .font(.subheadline).buttonStyle(.plain).foregroundStyle(NavigationStyle.accent)
            .frame(minHeight: 44)
        }
    }

    private func search(_ tracker: Tracker) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search \(tracker.name)", text: $query)
                    .font(.subheadline).padding(10)
                    .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { Task { await runSearch(tracker) } }
                Button("Cancel") { searchingTracker = nil; results = [] }.font(.subheadline)
            }
            if searching { ProgressView().frame(maxWidth: .infinity) }
            ForEach(results) { result in
                Button {
                    Task { await bind(result, tracker: tracker) }
                } label: {
                    HStack(spacing: 12) {
                        CoverImage(url: result.coverUrl.flatMap(URL.init(string:)), symbol: "Book")
                            .frame(width: 40, height: 58).clipShape(RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.title).font(.subheadline).multilineTextAlignment(.leading)
                            Text([result.publishingStatus, result.totalChapters.map { "\($0) \(isAnime ? "episodes" : "chapters")" }]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !searching && results.isEmpty {
                Text("No matches. Try a shorter or alternative title.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func load() async {
        struct Response: Decodable, Sendable {
            struct Media: Decodable, Sendable { let trackLinks: [TrackLink] }
            let trackers: [Tracker]
            let media: Media?
        }
        do {
            let response: Response = try await BackendAPI.shared.graphql(
                "{ trackers { key name isLoggedIn scoreOptions statusOptions { value name animeName } } media(id: \(BackendAPI.literal(mediaID))) { trackLinks { \(Self.linkFields) } } }",
                refresh: true, requiresSourceRuntime: false)
            trackers = response.trackers
            links = response.media?.trackLinks ?? []
            error = nil
        } catch { self.error = "Couldn’t load trackers. Try again." }
        loading = false
    }

    private func runSearch(_ tracker: Tracker) async {
        searching = true
        defer { searching = false }
        struct Response: Decodable, Sendable { let trackSearch: [TrackResult] }
        do {
            let response: Response = try await BackendAPI.shared.graphql(
                "{ trackSearch(trackerKey: \(BackendAPI.literal(tracker.key)), query: \(BackendAPI.literal(query)), contentType: \(isAnime ? "ANIME" : "MANGA")) { remoteId title coverUrl totalChapters publishingStatus } }",
                requiresSourceRuntime: false)
            results = response.trackSearch
        } catch { self.error = "Search failed. Check your connection and try again." }
    }

    private func bind(_ result: TrackResult, tracker: Tracker) async {
        await mutate("bindTrack(mediaId: \(BackendAPI.literal(mediaID)), trackerKey: \(BackendAPI.literal(tracker.key)), remoteId: \(BackendAPI.literal(result.remoteId))) { \(Self.linkFields) }")
        searchingTracker = nil
        results = []
        Toaster.shared.show("Now tracking on \(tracker.name)")
    }

    private func update(_ link: TrackLink, status: Int? = nil, progress: Double? = nil, score: Double? = nil) async {
        var arguments = ["linkId: \(BackendAPI.literal(link.id))"]
        if let status { arguments.append("status: \(status)") }
        if let progress { arguments.append("lastChapterRead: \(progress)") }
        if let score { arguments.append("score: \(score)") }
        await mutate("updateTrack(\(arguments.joined(separator: ", "))) { \(Self.linkFields) }")
    }

    private func mutate(_ body: String) async {
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql("mutation { \(body) }", requiresSourceRuntime: false)
            await load()
        } catch { self.error = "The tracker didn’t accept that change. Try again." }
    }
}

import SwiftUI

/// Links a title to each signed-in tracker to edit status, progress and score, pull, or unlink.
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
        struct Status: Decodable, Sendable {
            let value: Int
            let name: String
            let animeName: String
        }
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

    private static let linkFields =
        "id trackerKey title url status lastChapterRead totalChapters score"

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading trackers…").foregroundStyle(.secondary)
                        }
                    }
                } else if trackers.filter(\.isLoggedIn).isEmpty {
                    ContentUnavailableView(
                        "No Tracker Connected", systemImage: "antenna.radiowaves.left.and.right",
                        description: Text(
                            "Sign in to AniList in Settings → Tracking, then come back to link this title."
                        )
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(trackers.filter(\.isLoggedIn)) { tracker in
                    section(tracker)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.orange) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle("Tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private func section(_ tracker: Tracker) -> some View {
        Section(tracker.name) {
            if let link = links.first(where: { $0.trackerKey == tracker.key }) {
                linked(link, tracker: tracker)
            } else if searchingTracker == tracker.key {
                search(tracker)
            } else {
                LabeledContent {
                    Button("Link") {
                        searchingTracker = tracker.key
                        query = title
                        Task { await runSearch(tracker) }
                    }
                    .buttonStyle(.bordered)
                } label: {
                    Text("Not linked")
                    Text("Find this title on \(tracker.name) to sync your progress.")
                }
            }
        }
    }

    @ViewBuilder private func linked(_ link: TrackLink, tracker: Tracker) -> some View {
        if let url = URL(string: link.url) {
            Link(destination: url) {
                LabeledContent {
                    Image(systemName: "arrow.up.right.square")
                } label: {
                    Text(link.title).foregroundStyle(.primary)
                    Text("Now tracking")
                }
            }
            .accessibilityHint("Opens on \(tracker.name)")
        } else {
            LabeledContent {
                EmptyView()
            } label: {
                Text(link.title)
                Text("Now tracking")
            }
        }
        Picker(
            "Status",
            selection: Binding(
                get: { link.status },
                set: { value in Task { await update(link, status: value) } }
            )
        ) {
            if !tracker.statusOptions.contains(where: { $0.value == link.status }) {
                Text("Choose").tag(link.status)
            }
            ForEach(tracker.statusOptions, id: \.value) { option in
                Text(isAnime ? option.animeName : option.name).tag(option.value)
            }
        }
        Stepper(
            value: Binding(
                get: { link.lastChapterRead },
                set: { value in Task { await update(link, progress: value) } }),
            in: 0...Double(max(link.totalChapters, 10_000)), step: 1
        ) {
            LabeledContent(isAnime ? "Episodes watched" : "Chapters read") {
                Text(
                    link.lastChapterRead.formatted()
                        + (link.totalChapters > 0 ? " of \(link.totalChapters)" : "")
                )
                .monospacedDigit()
            }
        }
        if !tracker.scoreOptions.isEmpty {
            Menu {
                ForEach(tracker.scoreOptions, id: \.self) { option in
                    Button(option) { Task { await update(link, score: Double(option) ?? 0) } }
                }
            } label: {
                LabeledContent("Score") {
                    Text(link.score == 0 ? "No score" : link.score.formatted())
                }
            }
            .foregroundStyle(.primary)
        }
        Button {
            Task {
                await mutate(
                    "resyncTrack(linkId: \(BackendAPI.literal(link.id))) { \(Self.linkFields) }")
            }
        } label: {
            Label("Sync from \(tracker.name)", systemImage: "arrow.triangle.2.circlepath")
        }
        Button(role: .destructive) {
            Task {
                let _: IgnoredGraphQLResult? = try? await BackendAPI.shared.graphql(
                    "mutation { unbindTrack(linkId: \(BackendAPI.literal(link.id))) }",
                    requiresSourceRuntime: false)
                await load()
            }
        } label: {
            Label("Unlink", systemImage: "link.badge.minus")
        }
    }

    @ViewBuilder private func search(_ tracker: Tracker) -> some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search \(tracker.name)", text: $query)
                .submitLabel(.search)
                .onSubmit { Task { await runSearch(tracker) } }
            Button("Cancel") {
                searchingTracker = nil
                results = []
            }
            .buttonStyle(.borderless)
        }
        if searching { ProgressView().frame(maxWidth: .infinity) }
        ForEach(results) { result in
            Button {
                Task { await bind(result, tracker: tracker) }
            } label: {
                HStack(spacing: 12) {
                    CoverImage(
                        url: result.coverUrl.flatMap(URL.init(string:)), symbol: "book.closed"
                    )
                    .frame(width: 40, height: 58).clipShape(RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.title).font(.subheadline).multilineTextAlignment(.leading)
                        Text(
                            [
                                result.publishingStatus,
                                result.totalChapters.map {
                                    "\($0) \(isAnime ? "episodes" : "chapters")"
                                },
                            ]
                            .compactMap { $0 }.joined(separator: " · ")
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
        }
        if !searching && results.isEmpty {
            Text("No matches. Try a shorter or alternative title.").font(.caption).foregroundStyle(
                .secondary)
        }
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
        await mutate(
            "bindTrack(mediaId: \(BackendAPI.literal(mediaID)), trackerKey: \(BackendAPI.literal(tracker.key)), remoteId: \(BackendAPI.literal(result.remoteId))) { \(Self.linkFields) }"
        )
        searchingTracker = nil
        results = []
        Toaster.shared.show("Now tracking on \(tracker.name)")
    }

    private func update(
        _ link: TrackLink, status: Int? = nil, progress: Double? = nil, score: Double? = nil
    ) async {
        var arguments = ["linkId: \(BackendAPI.literal(link.id))"]
        if let status { arguments.append("status: \(status)") }
        if let progress { arguments.append("lastChapterRead: \(progress)") }
        if let score { arguments.append("score: \(score)") }
        await mutate("updateTrack(\(arguments.joined(separator: ", "))) { \(Self.linkFields) }")
    }

    private func mutate(_ body: String) async {
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                "mutation { \(body) }", requiresSourceRuntime: false)
            await load()
        } catch { self.error = "The tracker didn’t accept that change. Try again." }
    }
}

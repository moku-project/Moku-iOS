import SwiftUI

/// Links a title to its AniList entry so the server can fill in details, alternate covers and MyAnimeList links.
struct MetadataSheet: View {
    let mediaID: String
    let title: String
    let media: ContentMode
    var changed: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var match: Match?
    @State private var loading = true
    @State private var query = ""
    @State private var results: [Candidate] = []
    @State private var searching = false
    @State private var working = false
    @State private var error: String?

    struct Match: Decodable, Sendable {
        let provider: String
        let providerId: String
        let url: String
        let coverUrl: String?
        let confidence: Double
        let locked: Bool
    }

    struct Candidate: Decodable, Identifiable, Sendable {
        let provider: String
        let providerId: String
        let title: String
        let url: String
        let coverUrl: String?
        let status: String?
        let startYear: Int?
        var id: String { provider + providerId }
    }

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    Section {
                        HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                    }
                } else {
                    Section("Current match") {
                        if let match {
                            LabeledContent {
                                if let url = URL(string: match.url) {
                                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                                        .accessibilityLabel("Open match")
                                }
                            } label: {
                                Text(match.provider == "anilist" ? "AniList" : match.provider.capitalized)
                                Text(match.locked
                                    ? "Chosen by you"
                                    : "Matched automatically · \(Int(match.confidence * 100))% confident")
                            }
                            Button {
                                run("refreshMetadataMatch(mediaId: \(BackendAPI.literal(mediaID))) { id }", done: "Details refreshed")
                            } label: {
                                Label("Refresh Details", systemImage: "arrow.clockwise")
                            }
                            .disabled(working)
                            Button(role: .destructive) {
                                run("unlinkMetadata(mediaId: \(BackendAPI.literal(mediaID)))", done: "Match removed")
                            } label: {
                                Label("Unlink", systemImage: "link.badge.minus")
                            }
                            .disabled(working)
                        } else {
                            LabeledContent {
                                EmptyView()
                            } label: {
                                Text("Not matched")
                                Text("Search below and pick the right entry.")
                            }
                        }
                    }
                    Section {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search AniList", text: $query)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .submitLabel(.search).onSubmit { Task { await search() } }
                        }
                        if searching {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            ForEach(results) { candidate in candidateRow(candidate) }
                        }
                    } header: {
                        Text("Find a match")
                    } footer: {
                        if let error { Text(error).foregroundStyle(.orange) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle("Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                query = title
                await load()
                if match == nil { await search() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func candidateRow(_ candidate: Candidate) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: candidate.coverUrl.flatMap(URL.init(string:)), symbol: media.symbol)
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title).font(.subheadline.weight(.medium)).lineLimit(2)
                let detail = [candidate.startYear.map(String.init), candidate.status.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }]
                    .compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if match?.providerId == candidate.providerId {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(NavigationStyle.accent)
                    .accessibilityLabel("Current match")
            } else {
                Button("Use") {
                    run("applyMetadataMatch(mediaId: \(BackendAPI.literal(mediaID)), providerId: \(BackendAPI.literal(candidate.providerId)), provider: \(BackendAPI.literal(candidate.provider))) { id }",
                        done: "Matched to \(candidate.title)")
                }
                .buttonStyle(.bordered).disabled(working)
            }
        }
    }

    private func load() async {
        struct Response: Decodable, Sendable {
            struct Media: Decodable, Sendable { let metadata: Match? }
            let media: Media?
        }
        do {
            let response: Response = try await BackendAPI.shared.graphql(
                "{ media(id: \(BackendAPI.literal(mediaID))) { metadata { provider providerId url coverUrl confidence locked } } }",
                requiresSourceRuntime: false)
            match = response.media?.metadata
        } catch {
            self.error = "Couldn’t load the current match. Try again."
        }
        loading = false
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !searching else { return }
        struct Response: Decodable, Sendable { let searchMetadata: [Candidate] }
        searching = true
        defer { searching = false }
        do {
            let response: Response = try await BackendAPI.shared.graphql(
                "{ searchMetadata(query: \(BackendAPI.literal(text)), contentType: \(media.graphQLType)) { provider providerId title url coverUrl status startYear } }",
                requiresSourceRuntime: false)
            results = response.searchMetadata
            error = results.isEmpty ? "No matches found. Try another title or spelling." : nil
        } catch {
            self.error = "Search failed. Check your connection and try again."
        }
    }

    private func run(_ mutation: String, done: String) {
        guard !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                    "mutation { \(mutation) }", requiresSourceRuntime: false)
                await load()
                changed()
                Toaster.shared.show(done)
            } catch {
                self.error = "That didn’t work. Try again."
            }
        }
    }
}

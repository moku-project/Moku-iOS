import SwiftUI

/// Desktop metadata match: link a title to its AniList entry, so the server can
/// fill in missing details, alternate covers and MyAnimeList links.
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if loading {
                        ContentSkeleton(style: .settings, count: 2)
                    } else {
                        GeneralSection("Current match") {
                            if let match {
                                GeneralRow(
                                    match.provider == "anilist" ? "AniList" : match.provider.capitalized,
                                    detail: match.locked
                                        ? "Chosen by you"
                                        : "Matched automatically · \(Int(match.confidence * 100))% confident"
                                ) {
                                    if let url = URL(string: match.url) {
                                        Link(destination: url) { PhosphorIcon("ArrowUpRight", size: 14) }
                                            .accessibilityLabel("Open match")
                                    }
                                }
                                GeneralStyle.divider
                                GeneralRow("Refresh", detail: "Fetch the latest details from the match.") {
                                    Button("Refresh") { run("refreshMetadataMatch(mediaId: \(BackendAPI.literal(mediaID))) { id }", done: "Details refreshed") }
                                        .buttonStyle(GeneralTextButtonStyle()).disabled(working)
                                }
                                GeneralStyle.divider
                                GeneralRow("Unlink", detail: "Keep the source’s own details only.") {
                                    Button("Unlink") { run("unlinkMetadata(mediaId: \(BackendAPI.literal(mediaID)))", done: "Match removed") }
                                        .buttonStyle(GeneralTextButtonStyle()).disabled(working)
                                }
                            } else {
                                GeneralRow("Not matched", detail: "Search below and pick the right entry.") { EmptyView() }
                            }
                        }
                        GeneralSection("Find a match") {
                            HStack(spacing: 8) {
                                TextField("Search AniList", text: $query)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .submitLabel(.search).onSubmit { Task { await search() } }
                                    .generalInput()
                                Button("Search") { Task { await search() } }
                                    .buttonStyle(GeneralTextButtonStyle())
                                    .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            .padding(.vertical, 8)
                            if searching {
                                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                            } else {
                                ForEach(results) { candidate in
                                    GeneralStyle.divider
                                    candidateRow(candidate)
                                }
                            }
                        }
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                    }
                }
                .padding(20)
            }
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
                    Text(detail).font(.caption).foregroundStyle(GeneralStyle.label)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if match?.providerId == candidate.providerId {
                PhosphorIcon("CheckCircle.fill").foregroundStyle(NavigationStyle.accent)
                    .accessibilityLabel("Current match")
            } else {
                Button("Use") {
                    run("applyMetadataMatch(mediaId: \(BackendAPI.literal(mediaID)), providerId: \(BackendAPI.literal(candidate.providerId)), provider: \(BackendAPI.literal(candidate.provider))) { id }",
                        done: "Matched to \(candidate.title)")
                }
                .buttonStyle(GeneralTextButtonStyle()).disabled(working)
            }
        }
        .padding(.vertical, 8)
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

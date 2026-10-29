import SwiftUI

/// Desktop "Switch source" (MigrateModal): move a series to another installed
/// source. Read progress carries over by chapter number; downloads stay behind.
struct MigrateSheet: View {
    let mediaID: String
    let title: String
    let media: ContentMode
    let currentSource: String
    let migrated: (MediaEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sources: [Source] = []
    @State private var source: Source?
    @State private var query: String
    @State private var results: [MediaEntry] = []
    @State private var searching = false
    @State private var confirm: MediaEntry?
    @State private var working = false
    @State private var error: String?

    struct Source: Decodable, Identifiable, Hashable, Sendable {
        let id: String
        let packageName: String
        let displayName: String
        let lang: String
        let contentType: String
    }

    init(mediaID: String, title: String, media: ContentMode, currentSource: String, migrated: @escaping (MediaEntry) -> Void) {
        self.mediaID = mediaID
        self.title = title
        self.media = media
        self.currentSource = currentSource
        self.migrated = migrated
        _query = State(initialValue: title)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Source") {
                    Picker("Move to", selection: $source) {
                        Text("Choose a source").tag(Source?.none)
                        ForEach(sources) { item in
                            Text("\(item.displayName) · \(item.lang.uppercased())").tag(Source?.some(item))
                        }
                    }
                }
                if source != nil {
                    Section("Find the title") {
                        TextField("Search title", text: $query)
                            .onSubmit { Task { await search() } }
                        if searching { ProgressView().frame(maxWidth: .infinity) }
                        ForEach(results) { result in
                            Button { confirm = result } label: {
                                HStack(spacing: 12) {
                                    CoverImage(url: result.coverURL, symbol: result.media.symbol)
                                        .frame(width: 40, height: 58).clipShape(RoundedRectangle(cornerRadius: 4))
                                    Text(result.title).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    if Self.score(result.title, title) > 0.8 {
                                        Text("Best match").font(.caption2).foregroundStyle(NavigationStyle.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if !searching && results.isEmpty {
                            Text("No results yet. Search, or try another source.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Text("Read progress carries over by chapter number. The title is removed from \(currentSource) and its downloads are not moved.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
            }
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle("Switch source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await loadSources() }
            .onChange(of: source) { _, _ in Task { await search() } }
            .confirmationDialog(
                "Move to \(source?.displayName ?? "this source")?",
                isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                titleVisibility: .visible
            ) {
                Button("Switch source") { if let confirm { Task { await migrate(confirm) } } }
            } message: {
                Text(confirm?.title ?? "")
            }
            .disabled(working)
        }
    }

    private func loadSources() async {
        struct Response: Decodable, Sendable { let installedExtensions: [Source] }
        let kind = media == .anime ? "ANIME" : media == .novels ? "NOVEL" : "MANGA"
        do {
            let response: Response = try await BackendAPI.shared.graphql(
                "{ installedExtensions { id packageName displayName lang contentType } }", requiresSourceRuntime: false)
            sources = response.installedExtensions.filter { $0.contentType == kind && $0.displayName != currentSource }
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            if sources.isEmpty { error = "Install another \(media.title.lowercased()) source to switch to." }
        } catch { self.error = "Couldn’t load sources." }
    }

    private func search() async {
        guard let source, !query.isEmpty else { return }
        searching = true
        defer { searching = false }
        let request = SearchRequest(query: query, options: SearchOptions(media: media, sourceID: source.packageName))
        do {
            results = try await LiveMediaRepository.shared.search(request)
                .sorted { Self.score($0.title, title) > Self.score($1.title, title) }
            error = nil
        } catch {
            results = []
            self.error = (error as? EmbeddedSearchError)?.errorDescription ?? "Search failed."
        }
    }

    private func migrate(_ target: MediaEntry) async {
        guard let source, let externalID = target.externalID else { return }
        working = true
        defer { working = false }
        struct Response: Decodable, Sendable {
            struct Media: Decodable, Sendable { let id: String }
            let migrateMedia: Media
        }
        do {
            let response: Response = try await BackendAPI.shared.graphql(
                "mutation { migrateMedia(fromMediaId: \(BackendAPI.literal(mediaID)), toExtensionId: \(BackendAPI.literal(source.id)), toExternalId: \(BackendAPI.literal(externalID))) { id } }")
            let moved = MediaEntry(
                id: response.migrateMedia.id, title: target.title, media: target.media,
                sourceName: source.displayName, coverURL: target.coverURL,
                extensionID: source.packageName, externalID: externalID)
            Toaster.shared.show("Moved to \(source.displayName)")
            dismiss()
            migrated(moved)
        } catch {
            self.error = "Couldn’t switch source. Try another match."
        }
    }

    /// Token overlap between titles, 0…1, used to rank and badge matches.
    static func score(_ a: String, _ b: String) -> Double {
        func tokens(_ value: String) -> Set<String> {
            Set(value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        let left = tokens(a), right = tokens(b)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(left.union(right).count)
    }
}

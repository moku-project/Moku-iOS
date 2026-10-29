import SwiftUI

/// Desktop's Local source library: the series imported from files, with
/// rescan and delete (which removes the files from this device).
struct LocalLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @State private var items: [Item] = []
    @State private var loading = true
    @State private var deleting: Item?
    @State private var error: String?

    struct Item: Decodable, Identifiable, Sendable {
        let id: String
        let title: String
        let contentType: String
        let thumbnailUrl: String?
        var media: ContentMode { contentType == "ANIME" ? .anime : contentType == "NOVEL" ? .novels : .manga }
    }

    var body: some View {
        NavigationStack {
            List {
                if loading && items.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                } else if items.isEmpty {
                    Text("No local titles yet. Import a file in Settings › Storage › Local files.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        CoverImage(url: BackendAPI.coverURL(item.thumbnailUrl), symbol: item.media.symbol)
                            .frame(width: 36, height: 52).clipShape(RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.subheadline).lineLimit(2)
                            Text(item.media.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleting = item }
                    }
                    .contextMenu {
                        Button("Delete", phosphor: "Trash", role: .destructive) { deleting = item }
                    }
                }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            .textCase(nil)
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .refreshable { await rescan() }
            .navigationTitle("Local titles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Rescan") { Task { await rescan() } }.disabled(loading)
                }
            }
            .confirmationDialog("Delete \(deleting?.title ?? "this title")?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible
            ) {
                Button("Delete files", role: .destructive) { if let deleting { Task { await delete(deleting) } } }
            } message: {
                Text("Its imported files are removed from this device.")
            }
            .task { await load() }
        }
    }

    private func load() async {
        struct Response: Decodable, Sendable {
            struct Page: Decodable, Sendable { let results: [Item]; let hasNextPage: Bool }
            let localSourceSearch: Page
        }
        loading = true
        defer { loading = false }
        var all: [Item] = []
        do {
            for page in 1...20 {
                let response: Response = try await BackendAPI.shared.graphql(
                    "{ localSourceSearch(query: \"\", page: \(page)) { results { id title contentType thumbnailUrl } hasNextPage } }",
                    requiresSourceRuntime: false)
                all += response.localSourceSearch.results
                if !response.localSourceSearch.hasNextPage { break }
            }
            items = all.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            error = nil
        } catch {
            self.error = "Couldn’t load local titles. Pull to rescan."
        }
    }

    private func rescan() async {
        let _: IgnoredGraphQLResult? = try? await BackendAPI.shared.graphql(
            "mutation { rescanLocalMedia { id } }", requiresSourceRuntime: false)
        await load()
    }

    private func delete(_ item: Item) async {
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                "mutation { deleteLocalSeries(mediaId: \(BackendAPI.literal(item.id))) }", requiresSourceRuntime: false)
            items.removeAll { $0.id == item.id }
            library.invalidateServerVisibility()
            Toaster.shared.show("Deleted \(item.title)")
        } catch {
            self.error = "Couldn’t delete \(item.title). Try again."
        }
    }
}

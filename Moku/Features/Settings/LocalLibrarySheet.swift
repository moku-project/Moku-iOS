import SwiftUI

/// Series imported from files, with rescan and delete (which removes the files from this device).
struct LocalLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @State private var items: [Item] = []
    @State private var loading = true
    @State private var deleting: Item?
    @State private var renaming: Item?
    @State private var newTitle = ""
    @State private var error: String?

    struct Item: Decodable, Identifiable, Sendable {
        let id: String
        var title: String
        let contentType: String
        let thumbnailUrl: String?
        var media: ContentMode {
            contentType == "ANIME" ? .anime : contentType == "NOVEL" ? .novels : .manga
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if loading && items.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                } else if items.isEmpty {
                    Text("Import files in Settings › Storage.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        CoverImage(
                            url: BackendAPI.coverURL(item.thumbnailUrl), symbol: item.media.symbol
                        )
                        .frame(width: 36, height: 52).clipShape(RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.subheadline).lineLimit(2)
                            Text(item.media.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleting = item }
                        Button("Rename") { startRename(item) }
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { startRename(item) }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deleting = item
                        }
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
            .confirmationDialog(
                "Delete \(deleting?.title ?? "this title")?",
                isPresented: Binding(
                    get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete files", role: .destructive) {
                    if let deleting { Task { await delete(deleting) } }
                }
            } message: {
                Text("Its imported files are removed from this device.")
            }
            .alert(
                "Rename Series",
                isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
            ) {
                TextField("Title", text: $newTitle)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { if let renaming { Task { await rename(renaming) } } }
            } message: {
                Text("The series folder on this device is renamed too.")
            }
            .task { await load() }
        }
    }

    private func load() async {
        struct Response: Decodable, Sendable {
            struct Page: Decodable, Sendable {
                let results: [Item]
                let hasNextPage: Bool
            }
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

    private func startRename(_ item: Item) {
        newTitle = item.title
        renaming = item
    }

    private func rename(_ item: Item) async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != item.title else { return }
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                "mutation { renameLocalSeries(mediaId: \(BackendAPI.literal(item.id)), newTitle: \(BackendAPI.literal(title))) { id } }",
                requiresSourceRuntime: false)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].title = title
            }
            library.invalidateServerVisibility()
            _ = await library.refreshFromServer()
            Toaster.shared.show("Renamed to \(title)")
        } catch {
            self.error = "Couldn’t rename \(item.title). Try again."
        }
    }

    private func delete(_ item: Item) async {
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                "mutation { deleteLocalSeries(mediaId: \(BackendAPI.literal(item.id))) }",
                requiresSourceRuntime: false)
            items.removeAll { $0.id == item.id }
            library.invalidateServerVisibility()
            Toaster.shared.show("Deleted \(item.title)")
        } catch {
            self.error = "Couldn’t delete \(item.title). Try again."
        }
    }
}

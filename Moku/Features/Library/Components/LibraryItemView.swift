import SwiftUI

struct LibraryItemView: View {
    let item: LibraryItem
    let list: Bool
    let model: LibraryViewModel
    let layout: LibraryLayout
    let onOpen: (MediaEntry) -> Void
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Button {
            if model.selecting {
                model.toggleSelection(item)
            } else {
                if let entry = library.entries.first(where: { $0.id == item.id }) { onOpen(entry) }
            }
        } label: {
            LibraryCard(
                item: item, list: list, selected: model.selected.contains(item.id),
                compact: layout == .compactGrid || layout == .compactList,
                coversOnly: layout == .covers)
        }.buttonStyle(.plain)
            .contextMenu {
                Button(
                    item.bookmarked ? "Unstar" : "Star",
                    phosphor: item.bookmarked ? "Star" : "Star"
                ) {
                    Task {
                        var next = library.organization
                        if !next.starred.insert(item.id).inserted { next.starred.remove(item.id) }
                        if !(await library.saveOrganization(next)) { model.notice = library.error }
                    }
                }
                Menu("Folders", phosphor: "FolderSimple") {
                    ForEach(library.organization.folders) { folder in
                        Button(
                            folder.entryIDs.contains(item.id)
                                ? "Remove from \(folder.name)" : folder.name
                        ) {
                            Task {
                                var next = library.organization
                                if let index = next.folders.firstIndex(where: { $0.id == folder.id }
                                ) {
                                    if !next.folders[index].entryIDs.insert(item.id).inserted {
                                        next.folders[index].entryIDs.remove(item.id)
                                    }
                                    if !(await library.saveOrganization(next)) {
                                        model.notice = library.error
                                    }
                                }
                            }
                        }
                    }
                }
                if let entry = library.entries.first(where: { $0.id == item.id }) {
                    Button("Refresh chapters", phosphor: "ArrowsClockwise") {
                        Task { await LibraryActions.refresh([entry], model: model) }
                    }
                    if item.downloaded {
                        Button("Delete downloads", phosphor: "Trash") {
                            Task { await LibraryActions.deleteDownloads([entry.id], model: model) }
                        }
                    }
                    Button("Remove from library", phosphor: "Bookmark", role: .destructive) {
                        Task { await LibraryActions.remove([entry], library: library, model: model) }
                    }
                }
                Divider()
                Button("Select", phosphor: "CheckSquare") {
                    model.selecting = true
                    model.selected = [item.id]
                }
            }

    }
}

/// Card menu and selection-bar actions, shared so single and bulk paths match.
@MainActor enum LibraryActions {
    static func refresh(_ entries: [MediaEntry], model: LibraryViewModel) async {
        var failed = 0
        for entry in entries where Int64(entry.id) != nil {
            do {
                let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                    "mutation { syncChapters(mediaId: \(BackendAPI.literal(entry.id))) { id } }")
            } catch { failed += 1 }
        }
        if failed > 0 {
            Toaster.shared.show("Refresh failed", detail: "\(failed) of \(entries.count) couldn’t refresh.", kind: .error)
        } else {
            Toaster.shared.show(entries.count == 1 ? "Refreshed" : "Refreshed \(entries.count) titles")
        }
    }

    static func deleteDownloads(_ ids: [String], model: LibraryViewModel) async {
        var failed = 0
        for id in ids where Int64(id) != nil {
            do {
                struct Media: Decodable, Sendable {
                    struct Item: Decodable, Sendable { let chapters: [Chapter] }
                    let media: Item?
                }
                let media: Media = try await BackendAPI.shared.graphql(
                    "{ media(id: \(BackendAPI.literal(id))) { chapters { id title number scanlator completed downloaded } } }",
                    requiresSourceRuntime: false)
                let chapters = media.media?.chapters.filter(\.downloaded).map(\.id) ?? []
                guard !chapters.isEmpty else { continue }
                let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                    "mutation { deleteDownload(mediaId: \(BackendAPI.literal(id)), chapterIds: [\(chapters.map(BackendAPI.literal).joined(separator: ","))]) }",
                    requiresSourceRuntime: false)
            } catch { failed += 1 }
        }
        Toaster.shared.show(failed == 0 ? "Downloads deleted" : "Some downloads couldn’t be deleted",
                            kind: failed == 0 ? .success : .error)
    }

    static func remove(_ entries: [MediaEntry], library: LibraryStore, model: LibraryViewModel) async {
        var removed = 0
        for entry in entries where await library.setSaved(false, entry: entry) { removed += 1 }
        model.selected.subtract(entries.map(\.id))
        if removed == entries.count {
            Toaster.shared.show(removed == 1 ? "Removed from library" : "Removed \(removed) titles")
        } else {
            Toaster.shared.show("Remove failed", detail: library.error, kind: .error)
        }
    }

    static func move(_ ids: Set<String>, to folderID: UUID?, library: LibraryStore, model: LibraryViewModel) async {
        var next = library.organization
        for index in next.folders.indices {
            if next.folders[index].id == folderID {
                next.folders[index].entryIDs.formUnion(ids)
            } else if folderID == nil, model.folder?.id == next.folders[index].id {
                next.folders[index].entryIDs.subtract(ids)
            }
        }
        if await library.saveOrganization(next) {
            let name = next.folders.first { $0.id == folderID }?.name
            Toaster.shared.show(name.map { "Moved to \($0)" } ?? "Removed from folder")
        } else {
            Toaster.shared.show("Couldn’t update folders", detail: library.error, kind: .error)
        }
    }
}

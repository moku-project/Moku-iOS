import SwiftUI

struct LibraryItemView: View {
    let item: LibraryItem
    let list: Bool
    let model: LibraryViewModel
    let layout: LibraryLayout
    let onOpen: (MediaEntry) -> Void
    @Environment(ProfileLibrary.self) private var library

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
            }

    }
}

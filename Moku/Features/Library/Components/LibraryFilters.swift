import SwiftUI

struct LibraryFilters: View {
    let optionDraft: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Filters").font(.title2.bold())
            SearchOptionSection(title: "Sort by") {
                ForEach(LibrarySort.allCases) { sort in
                    SearchOptionChoice(
                        title: sort.rawValue, symbol: "SortAscending",
                        selected: optionDraft.sort == sort
                    ) {
                        optionDraft.sort = sort
                    }
                }
            }
            SearchOptionSection(title: "Direction") {
                SearchOptionChoice(
                    title: "Ascending", symbol: "ArrowUp", selected: optionDraft.ascending
                ) { optionDraft.ascending = true }
                SearchOptionChoice(
                    title: "Descending", symbol: "ArrowDown", selected: !optionDraft.ascending
                ) { optionDraft.ascending = false }
            }
            SearchOptionSection(title: "Content") {
                SearchOptionChoice(
                    title: "Unread", symbol: "Book", selected: optionDraft.unreadOnly
                ) { optionDraft.unreadOnly.toggle() }
                SearchOptionChoice(
                    title: "Started", symbol: "BookOpen", selected: optionDraft.startedOnly
                ) { optionDraft.startedOnly.toggle() }
                SearchOptionChoice(
                    title: "Downloaded", symbol: "DownloadSimple",
                    selected: optionDraft.downloadedOnly
                ) { optionDraft.downloadedOnly.toggle() }
                SearchOptionChoice(
                    title: "Starred", symbol: "Star", selected: optionDraft.bookmarkedOnly
                ) { optionDraft.bookmarkedOnly.toggle() }
                SearchOptionChoice(
                    title: "Tracked", symbol: "Broadcast", selected: optionDraft.trackedOnly
                ) { optionDraft.trackedOnly.toggle() }
            }
            SearchOptionSection(title: "Status") {
                SearchOptionChoice(
                    title: "Any status", symbol: "SquaresFour", selected: optionDraft.status == nil
                ) { optionDraft.status = nil }
                ForEach(LibraryStatus.allCases) { status in
                    SearchOptionChoice(
                        title: status.rawValue, symbol: "Books",
                        selected: optionDraft.status == status
                    ) {
                        optionDraft.status = status
                    }
                }
            }
        }
        .padding(8)
    }

}

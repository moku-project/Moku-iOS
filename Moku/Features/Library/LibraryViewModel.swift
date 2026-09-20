import Foundation
import Observation

/// Presentation state for saved titles. Supply items when the library repository is connected.
@MainActor @Observable
final class LibraryViewModel {
    var items: [LibraryItem] = []
    var showAllInSaved = true
    var hideCompletedInSaved = false
    var disableAutoComplete = false
    var folderEntryIDs: Set<String> = []
    var tab: LibraryTab = .saved
    var folder: LibraryFolder?
    var query = ""
    var sort: LibrarySort = .title
    var ascending = true
    var unreadOnly = false
    var startedOnly = false
    var downloadedOnly = false
    var bookmarkedOnly = false
    var status: LibraryStatus?
    var selecting = false
    var selected: Set<String> = []
    var notice: String?

    var hasFilters: Bool {
        unreadOnly || startedOnly || downloadedOnly || bookmarkedOnly
            || status != nil
    }

    func scoped(to mode: ContentMode) -> [LibraryItem] {
        items.filter { mode == .all || $0.media == mode }
    }

    func count(_ tab: LibraryTab, mode: ContentMode) -> Int {
        scoped(to: mode).filter { matches($0, tab: tab) }.count
    }

    func visible(mode: ContentMode) -> [LibraryItem] {
        return scoped(to: mode).filter {
            matches($0, tab: tab)
                && (folder?.entryIDs.contains($0.id) ?? true)
                && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))
                && (!unreadOnly || $0.unread > 0)
                && (!startedOnly || $0.readUnits > 0)
                && (!downloadedOnly || $0.downloaded)
                && (!bookmarkedOnly || $0.bookmarked)
                && (status == nil || $0.status == status)
        }.sorted { lhs, rhs in
            let order: ComparisonResult
            switch sort {
            case .title: order = lhs.title.localizedStandardCompare(rhs.title)
            case .unread: order = compare(lhs.unread, rhs.unread)
            case .total: order = compare(lhs.totalUnits, rhs.totalUnits)
            case .added: order = lhs.addedAt.compare(rhs.addedAt)
            case .read: order = lhs.lastRead.compare(rhs.lastRead)
            }
            if order == .orderedSame { return lhs.id < rhs.id }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    func clearFilters() {
        unreadOnly = false
        startedOnly = false
        downloadedOnly = false
        bookmarkedOnly = false
        status = nil
    }

    func toggleSelection(_ item: LibraryItem) {
        if !selected.insert(item.id).inserted { selected.remove(item.id) }
    }

    private func matches(_ item: LibraryItem, tab: LibraryTab) -> Bool {
        switch tab {
        case .saved:
            (folder != nil || showAllInSaved || !folderEntryIDs.contains(item.id))
                && (!hideCompletedInSaved || disableAutoComplete || !item.isCompleted)
        case .downloaded: item.downloaded
        case .starred: item.bookmarked
        case .reading: item.readUnits > 0 && (disableAutoComplete || !item.isCompleted)
        case .completed: !disableAutoComplete && item.isCompleted
        }
    }

    private func compare(_ lhs: Int, _ rhs: Int) -> ComparisonResult {
        lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
    }

}

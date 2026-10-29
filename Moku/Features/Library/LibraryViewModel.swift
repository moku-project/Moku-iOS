import Foundation
import Observation

/// Presentation state for saved titles. Supply items when the library repository is connected.
@MainActor @Observable
final class LibraryViewModel {
    var items: [LibraryItem] = [] { didSet { if items != oldValue { invalidateResults() } } }
    var showAllInSaved = true { didSet { if showAllInSaved != oldValue { invalidateResults() } } }
    var hideCompletedInSaved = false { didSet { if hideCompletedInSaved != oldValue { invalidateResults() } } }
    var disableAutoComplete = false { didSet { if disableAutoComplete != oldValue { invalidateResults() } } }
    var folderEntryIDs: Set<String> = [] { didSet { if folderEntryIDs != oldValue { invalidateResults() } } }
    var tab: LibraryTab = .saved { didSet { if tab != oldValue { invalidateResults() } } }
    var folder: LibraryFolder? { didSet { if folder != oldValue { invalidateResults() } } }
    var query = "" { didSet { if query != oldValue { invalidateResults() } } }
    var sort: LibrarySort = .title { didSet { if sort != oldValue { invalidateResults() } } }
    var ascending = true { didSet { if ascending != oldValue { invalidateResults() } } }
    var unreadOnly = false { didSet { if unreadOnly != oldValue { invalidateResults() } } }
    var startedOnly = false { didSet { if startedOnly != oldValue { invalidateResults() } } }
    var downloadedOnly = false { didSet { if downloadedOnly != oldValue { invalidateResults() } } }
    var bookmarkedOnly = false { didSet { if bookmarkedOnly != oldValue { invalidateResults() } } }
    var trackedOnly = false { didSet { if trackedOnly != oldValue { invalidateResults() } } }
    var status: LibraryStatus? { didSet { if status != oldValue { invalidateResults() } } }
    var selecting = false
    var selected: Set<String> = []
    var notice: String?

    private(set) var resultsRevision = 0
    @ObservationIgnored private var visibleCache: [ContentMode: [LibraryItem]] = [:]

    private func invalidateResults() {
        visibleCache.removeAll(keepingCapacity: true)
        resultsRevision &+= 1
    }

    var hasFilters: Bool {
        unreadOnly || startedOnly || downloadedOnly || bookmarkedOnly || trackedOnly
            || status != nil
    }

    func scoped(to mode: ContentMode) -> [LibraryItem] {
        items.filter { mode == .all || $0.media == mode }
    }

    func count(_ tab: LibraryTab, mode: ContentMode) -> Int {
        let input = selection(mode: mode)
        return items.reduce(0) { count, item in
            count + ((mode == .all || item.media == mode) && input.matches(item, tab: tab) ? 1 : 0)
        }
    }

    func visible(mode: ContentMode) -> [LibraryItem] {
        // Observe the revision even on cache hits, so view invalidation stays correct.
        _ = resultsRevision
        if let cached = visibleCache[mode] { return cached }
        let result = selection(mode: mode).evaluate()
        visibleCache[mode] = result
        return result
    }

    func clearFilters() {
        unreadOnly = false
        startedOnly = false
        downloadedOnly = false
        bookmarkedOnly = false
        trackedOnly = false
        status = nil
    }

    func toggleSelection(_ item: LibraryItem) {
        if !selected.insert(item.id).inserted { selected.remove(item.id) }
    }

    private func selection(mode: ContentMode) -> LibrarySelection {
        LibrarySelection(items: items, mode: mode, tab: tab, folder: folder,
                         query: query, sort: sort, ascending: ascending,
                         showAllInSaved: showAllInSaved, hideCompletedInSaved: hideCompletedInSaved,
                         disableAutoComplete: disableAutoComplete, folderEntryIDs: folderEntryIDs,
                         unreadOnly: unreadOnly, startedOnly: startedOnly, downloadedOnly: downloadedOnly,
                         bookmarkedOnly: bookmarkedOnly, trackedOnly: trackedOnly, status: status)
    }

    func prepareVisible(mode: ContentMode) async -> [LibraryItem] {
        guard !Task.isCancelled else { return [] }
        let revision = resultsRevision
        if let cached = visibleCache[mode] { return cached }
        let input = selection(mode: mode)
        let worker = Task.detached(priority: .userInitiated) { input.evaluate() }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: { worker.cancel() }
        guard !Task.isCancelled, revision == resultsRevision else { return [] }
        visibleCache[mode] = result
        return result
    }
}

private struct LibrarySelection: Sendable {
    let items: [LibraryItem]
    let mode: ContentMode
    let tab: LibraryTab
    let folder: LibraryFolder?
    let query: String
    let sort: LibrarySort
    let ascending: Bool
    let showAllInSaved: Bool
    let hideCompletedInSaved: Bool
    let disableAutoComplete: Bool
    let folderEntryIDs: Set<String>
    let unreadOnly: Bool
    let startedOnly: Bool
    let downloadedOnly: Bool
    let bookmarkedOnly: Bool
    let trackedOnly: Bool
    let status: LibraryStatus?

    func evaluate() -> [LibraryItem] {
        do {
            return try items.filter {
                try Task.checkCancellation()
                return (mode == .all || $0.media == mode)
                    && matches($0, tab: tab)
                    && (folder?.entryIDs.contains($0.id) ?? true)
                    && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))
                    && (!unreadOnly || $0.unread > 0)
                    && (!startedOnly || $0.hasStarted)
                    && (!downloadedOnly || $0.downloaded)
                    && (!bookmarkedOnly || $0.bookmarked)
                    && (!trackedOnly || $0.tracked)
                    && (status == nil || $0.status == status)
            }.sorted { lhs, rhs in
                try Task.checkCancellation()
                let order: ComparisonResult
                switch sort {
                case .title: order = lhs.title.localizedStandardCompare(rhs.title)
                case .unread: order = compare(lhs.unread, rhs.unread)
                case .total: order = compare(lhs.totalUnits, rhs.totalUnits)
                case .added: order = lhs.addedAt.compare(rhs.addedAt)
                case .read: order = lhs.lastRead.compare(rhs.lastRead)
                case .uploaded: order = lhs.latestUpload.compare(rhs.latestUpload)
                }
                if order == .orderedSame { return lhs.id < rhs.id }
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
        } catch { return [] }
    }

    func matches(_ item: LibraryItem, tab: LibraryTab) -> Bool {
        switch tab {
        case .saved:
            (folder != nil || showAllInSaved || !folderEntryIDs.contains(item.id))
                && (!hideCompletedInSaved || disableAutoComplete || !item.isCompleted)
        case .downloaded: item.downloaded
        case .starred: item.bookmarked
        case .reading: item.hasStarted && (disableAutoComplete || !item.isCompleted)
        case .completed: !disableAutoComplete && item.isCompleted
        }
    }

    func compare(_ lhs: Int, _ rhs: Int) -> ComparisonResult {
        lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
    }

}

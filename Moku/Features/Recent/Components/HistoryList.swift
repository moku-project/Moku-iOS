import SwiftUI

struct HistoryList: View {
    let home: HomeStore
    let history: [RecentHistoryDay]
    let historySearch: String
    let expanded: Set<String>
    let opening: Bool
    let open: (String, String?) -> Void
    let toggle: (String) -> Void
    let showStatistics: () -> Void
    let clear: (RecentHistoryTitle) -> Void
    var body: some View { historyContent }
    @ViewBuilder private var historyContent: some View {
        if let error = home.storageError { Text(error).font(.footnote).foregroundStyle(.red) }

        if !home.isLoaded {
            ContentSkeleton(style: .results)
        } else if history.isEmpty {
            empty(
                title: historySearch.isEmpty ? "Nothing here yet" : "No matching activity",
                subtitle: historySearch.isEmpty
                    ? "Your reading and watching history will appear here."
                    : "Try another title or chapter.",
                symbol: "ClockCounterClockwise")
        } else {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(history) { day in
                    Section {
                        ForEach(day.titles) {
                            item in
                            HistoryRow(
                                item: item, expanded: expanded.contains(item.id), opening: opening,
                                open: open, toggle: { toggle(item.id) }, showStatistics: showStatistics,
                                clear: clear)
                        }
                    } header: {
                        dayHeading(day.id)
                    }
                }
            }
        }
    }

    private func empty(title: String, subtitle: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 280)
            .accessibilityIdentifier("recent.empty")
    }
    private func dayHeading(_ date: Date) -> some View {
        HStack {
            Text(
                date < Date(timeIntervalSince1970: 0)
                    ? "Date unavailable"
                    : Calendar.current.isDateInToday(date)
                        ? "Today"
                        : Calendar.current.isDateInYesterday(date)
                            ? "Yesterday" : date.formatted(date: .abbreviated, time: .omitted)
            )
            .font(.subheadline).foregroundStyle(.secondary)

        }.accessibilityAddTraits(.isHeader)
    }

}

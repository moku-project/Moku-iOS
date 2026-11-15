import SwiftUI

/// History rows grouped by day, as List sections. Empty and loading states are drawn by RecentView.
struct HistoryList: View {
    let history: [RecentHistoryDay]
    let expanded: Set<String>
    let opening: Bool
    let open: (String, String?) -> Void
    let toggle: (String) -> Void
    let showStatistics: () -> Void
    let clear: (RecentHistoryTitle) -> Void

    var body: some View {
        ForEach(history) { day in
            Section {
                ForEach(day.titles) { item in
                    HistoryRow(
                        item: item, expanded: expanded.contains(item.id), opening: opening,
                        open: open, toggle: { toggle(item.id) }, showStatistics: showStatistics,
                        clear: clear)
                }
            } header: {
                Text(RecentDayTitle.text(day.id))
            }
        }
    }
}

enum RecentDayTitle {
    static func text(_ date: Date) -> String {
        if date < Date(timeIntervalSince1970: 0) { return "Date unavailable" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

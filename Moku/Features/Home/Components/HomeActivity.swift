import SwiftUI

/// Streak, chapters, read time and this week, side by side.
struct HomeStatsStrip: View {
    let statistics: HomeStatistics

    var body: some View {
        HStack(spacing: 0) {
            stat("flame.fill", "\(statistics.currentStreak)d", "Streak", tint: .orange)
            Divider().padding(.vertical, 4)
            stat("book", "\(statistics.units)", "Chapters")
            Divider().padding(.vertical, 4)
            stat("clock", Self.duration(minutes: statistics.minutes), "Read Time")
            Divider().padding(.vertical, 4)
            stat("calendar", "\(statistics.thisWeek)", "This Week")
        }
        .fixedSize(horizontal: false, vertical: true)
        .homeCard(padding: EdgeInsets(top: 14, leading: 4, bottom: 14, trailing: 4))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.stats")
    }

    static func duration(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func stat(_ symbol: String, _ value: String, _ label: String, tint: Color = .secondary)
        -> some View
    {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.footnote).foregroundStyle(tint).accessibilityHidden(
                true)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A fixed-width calendar heatmap that fits the page without scrolling.
struct HomeHeatmap: View {
    let daily: [Date: Int]
    let weeks: Int

    private static let gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            GeometryReader { geometry in
                let cell = (geometry.size.width - Self.gap * CGFloat(weeks - 1)) / CGFloat(weeks)
                HStack(spacing: Self.gap) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: Self.gap) {
                            ForEach(week.indices, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(color(for: week[index]))
                                    .frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
            .aspectRatio(CGFloat(weeks) / 7, contentMode: .fit)
            HStack(spacing: 4) {
                Text("Less")
                ForEach([0, 1, 3, 6, 9], id: \.self) { count in
                    RoundedRectangle(cornerRadius: 2).fill(level(count)).frame(width: 9, height: 9)
                }
                Text("More")
            }
            .font(.caption2).foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .homeCard(padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity over the last \(weeks) weeks")
        .accessibilityValue("\(Self.total(daily, weeks: weeks)) chapters or episodes")
        .accessibilityIdentifier("home.heatmap")
    }

    static func total(_ daily: [Date: Int], weeks: Int) -> Int {
        days(weeks: weeks).joined().compactMap { $0.map { daily[$0, default: 0] } }.reduce(0, +)
    }

    private var days: [[Date?]] { Self.days(weeks: weeks) }

    /// Columns of seven days ending this week; days after today are nil.
    private static func days(weeks: Int) -> [[Date?]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weekday = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -(weeks - 1) * 7 - weekday, to: today)!
        return (0..<weeks).map { week in
            (0..<7).map { offset in
                let day = calendar.date(byAdding: .day, value: week * 7 + offset, to: start)!
                return day > today ? nil : day
            }
        }
    }

    private func color(for day: Date?) -> Color {
        guard let day else { return .clear }
        return level(daily[day, default: 0])
    }

    private func level(_ count: Int) -> Color {
        switch count {
        case 0: AppTheme.shared.colors.border
        case 1: NavigationStyle.accent.opacity(0.3)
        case 2...3: NavigationStyle.accent.opacity(0.55)
        case 4...6: NavigationStyle.accent.opacity(0.8)
        default: NavigationStyle.accent
        }
    }
}

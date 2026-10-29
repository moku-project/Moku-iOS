import SwiftUI

struct HomeActivityView: View {
    let statistics: HomeStatistics
    @State private var weeks = 12
    @State private var selectedDay: Date?
    @State private var heatmapWidth: CGFloat = 320

    private var cellSize: CGFloat {
        max(16, (heatmapWidth - 18 - CGFloat(weeks - 1) * 4) / CGFloat(weeks))
    }
    private let media = ["Manga", "Novels", "Anime"]
    private let colors = [
        NavigationStyle.accent, Color(red: 0.49, green: 0.49, blue: 0.94),
        Color(red: 0.94, green: 0.63, blue: 0.35),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 14) {
                HStack {
                    Text("Activity").font(.headline)
                    Spacer()
                    ChoicePicker(
                        title: "", selection: $weeks,
                        options: [12, 26, 52].map { ($0, "Last \($0) weeks") }
                    )
                    .font(.caption)

                }
                heatmap
                HStack(spacing: 5) {
                    Spacer()
                    Text("Less")
                    ForEach(0..<5) { level in
                        RoundedRectangle(cornerRadius: 3).fill(heatColor(level)).frame(
                            width: 12, height: 12)
                    }
                    Text("More")
                }.font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeading(title: "Your stats")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 155), spacing: 24, alignment: .leading)],
                    alignment: .leading, spacing: 20
                ) {
                    stat("\(statistics.currentStreak)", "Day streak", "Fire.fill")
                    stat("\(statistics.bestStreak)", "Best streak", "TrendUp")
                    stat("\(statistics.units)", "Chapters / episodes", "BookOpen")
                    stat("\(statistics.minutes)", "Minutes spent", "Clock")
                    stat("\(statistics.thisWeek)", "Read · 7 days", "CalendarBlank")
                    stat(String(format: "%.1f", statistics.perDay), "Daily average", "TrendUp")
                    stat("\(statistics.series)", "Series started", "Books")
                    stat(
                        statistics.firstRead?.formatted(.dateTime.month(.abbreviated).year()) ?? "—",
                        "Since", "CalendarCheck")
                }
                .accessibilityIdentifier("home.stats")
            }
            VStack(alignment: .leading, spacing: 16) {
                HomeSectionHeading(title: "By type")
                if statistics.byMedia.values.reduce(0, +) == 0 {
                    HomeEmptyRow(text: "No completed chapters or episodes yet", symbol: "ChartPie")
                } else {
                    HStack(spacing: 24) {
                        donut.frame(width: 94, height: 94).accessibilityHidden(true)
                        VStack(spacing: 12) {
                            ForEach(Array(media.enumerated()), id: \.offset) { index, name in
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 3).fill(colors[index]).frame(
                                        width: 10, height: 10)
                                    Text(name)
                                    Spacer()
                                    Text("\(statistics.byMedia[name, default: 0])")
                                    Text("\(Int((fraction(index) * 100).rounded()))%")
                                        .foregroundStyle(.secondary)

                                }.font(.caption)
                            }
                        }
                    }
                }
            }

        }
    }

    private var heatmap: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endOfWeek = calendar.date(
            byAdding: .day, value: (8 - calendar.component(.weekday, from: today)) % 7, to: today)!
        let start = calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: endOfWeek)!
        return HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 4) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { row in
                    Text(["M", "T", "W", "T", "F", "S", "S"][row]).font(
                        .system(size: 9)
                    )
                    .foregroundStyle(.secondary).frame(width: 14, height: cellSize)
                }
            }.padding(.top, 20).accessibilityHidden(true)
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(0..<weeks, id: \.self) { week in
                        VStack(spacing: 4) {
                            let first = calendar.date(byAdding: .day, value: week * 7, to: start)!
                            let previous = calendar.date(byAdding: .day, value: -7, to: first)!
                            Text(week == 0 || calendar.component(.month, from: first) != calendar.component(.month, from: previous)
                                 ? first.formatted(.dateTime.month(.abbreviated)) : "")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                                .fixedSize().frame(width: cellSize, height: 16, alignment: .leading)
                                .accessibilityHidden(true)
                            ForEach(0..<7, id: \.self) { day in
                                let date = calendar.date(
                                    byAdding: .day, value: week * 7 + day, to: start)!
                                let count = statistics.daily[date, default: 0]
                                Button { selectedDay = date } label: {
                                    RoundedRectangle(cornerRadius: 3)
                                    .fill(heatColor(count == 0 ? 0 : min(4, 1 + count / 3)))
                                    .frame(width: cellSize, height: cellSize)
                                    .opacity(date > today ? 0.3 : 1)
                                    .overlay {
                                        if date == today {
                                            RoundedRectangle(cornerRadius: 3).strokeBorder(
                                                NavigationStyle.accent.opacity(0.7), lineWidth: 1)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(date > today)
                                .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)): \(count) chapters or episodes")
                                .popover(isPresented: Binding(
                                    get: { selectedDay == date },
                                    set: { if !$0 && selectedDay == date { selectedDay = nil } }
                                )) {
                                    VStack(spacing: 6) {
                                        Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                                        Text("\(count) chapters / episodes").font(.subheadline.weight(.medium))
                                    }.padding().presentationCompactAdaptation(.popover)
                                }
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.trailing)
            .defaultScrollAnchor(.leading, for: .alignment)
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("home.heatmap")
        }
        .frame(height: cellSize * 7 + 44)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { heatmapWidth = $0 }
    }

    private func heatColor(_ level: Int) -> Color {
        level == 0 ? Color.white.opacity(0.07) : NavigationStyle.accent.opacity(Double(level) / 4)
    }

    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PhosphorIcon(symbol).font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 22, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(.title2.weight(.semibold)).foregroundStyle(.primary)
                    .monospacedDigit()
                Text(label).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func fraction(_ index: Int) -> Double {
        Double(statistics.byMedia[media[index], default: 0])
            / Double(max(1, statistics.byMedia.values.reduce(0, +)))
    }

    private var donut: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.07), lineWidth: 13)
            ForEach(0..<3) { index in
                let start = (0..<index).reduce(0.0) { $0 + fraction($1) }
                Circle().trim(from: start, to: start + fraction(index))
                    .stroke(colors[index], style: StrokeStyle(lineWidth: 13, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

import SwiftUI

struct HomeActivityView: View {
    let statistics: HomeStatistics
    @State private var weeks = 12
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
                HStack(spacing: 12) {
                    PhosphorIcon("Fire.fill")
                        .foregroundStyle(statistics.currentStreak > 0 ? Color.orange : .gray)
                        .frame(width: 32, height: 40)
                    Text("\(statistics.currentStreak)").font(
                        .title2.weight(.medium))
                    Text("day streak").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Best").font(.caption2).foregroundStyle(.secondary)
                        Text("\(statistics.bestStreak) days").font(.caption)
                    }
                }
                .padding(12)
                .background(
                    statistics.currentStreak > 0
                        ? Color.orange.opacity(0.09) : Color.white.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(
                        statistics.currentStreak > 0
                            ? Color.orange.opacity(0.25) : .white.opacity(0.06), lineWidth: 0.5)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
                    tile("\(statistics.units)", "Chapters / episodes", "BookOpen")
                    tile(
                        "\(statistics.minutes / 60)h \(statistics.minutes % 60)m", "Read time",
                        "Clock")
                    tile("\(statistics.thisWeek)", "This week", "CalendarBlank")
                    tile(
                        String(format: "%.1f", statistics.perDay), "Per day",
                        "TrendUp")
                    tile("\(statistics.series)", "Series started", "Books")
                    tile(
                        statistics.firstRead?.formatted(.dateTime.month(.abbreviated).year())
                            ?? "—", "Reading since", "CalendarCheck")
                }
                .accessibilityIdentifier("home.stats")
            }
            VStack(alignment: .leading, spacing: 16) {
                HomeSectionHeading(title: "Read by type")
                if statistics.byMedia.values.reduce(0, +) == 0 {
                    HomeEmptyRow(text: "No reading tracked yet", symbol: "ChartPie")
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
                                    Text("\(Int((fraction(index) * 100).rounded()))%")

                                }.font(.caption)
                            }
                        }
                    }.padding(.horizontal, 8)
                }
            }
            HStack {
                Spacer()
                if let last = statistics.lastRead {
                    Text("Updated \(last.formatted(date: .abbreviated, time: .shortened))")
                } else {
                    Text("Updated —")
                }
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var heatmap: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endOfWeek = calendar.date(
            byAdding: .day, value: (8 - calendar.component(.weekday, from: today)) % 7, to: today)!
        let start = calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: endOfWeek)!
        return HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 4) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { row in
                    Text(["M", "T", "W", "T", "F", "S", "S"][row]).font(
                        .system(size: 9)
                    )
                    .foregroundStyle(.secondary).frame(height: 16)
                }
            }.accessibilityHidden(true)
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(0..<weeks, id: \.self) { week in
                        VStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { day in
                                let date = calendar.date(
                                    byAdding: .day, value: week * 7 + day, to: start)!
                                let count = statistics.daily[date, default: 0]
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(heatColor(count == 0 ? 0 : min(4, 1 + count / 3)))
                                    .frame(width: 20, height: 16)
                                    .opacity(date > today ? 0.3 : 1)
                                    .overlay {
                                        if date == today {
                                            RoundedRectangle(cornerRadius: 3).strokeBorder(
                                                NavigationStyle.accent.opacity(0.7), lineWidth: 1)
                                        }
                                    }
                                    .accessibilityLabel(
                                        "\(date.formatted(date: .abbreviated, time: .omitted)): \(count) activity"
                                    )
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.trailing)
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("home.heatmap")
        }
    }

    private func heatColor(_ level: Int) -> Color {
        level == 0 ? Color.white.opacity(0.07) : NavigationStyle.accent.opacity(Double(level) / 4)
    }

    private func tile(_ value: String, _ label: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            PhosphorIcon(symbol).font(.subheadline).foregroundStyle(.secondary).frame(
                width: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text(value).font(.body.weight(.medium))
                Text(label).font(.caption2).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
        }
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

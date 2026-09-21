import SwiftUI

struct UpdateList: View {
    let model: RecentViewModel
    let updates: [RecentUpdate]
    let updatesSearch: String
    let didLoad: Bool
    let expanded: Set<String>
    let toggle: (String) -> Void
    let open: (MediaEntry, String?) -> Void
    let refresh: () async -> Void
    var body: some View { updatesContent }
    @ViewBuilder private var updatesContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                model.refreshing
                    ? "Updating library · \(model.done)/\(model.total)"
                    : "\(Set(updates.map(\.mediaID)).count) updated titles"
            )
            .font(.subheadline).foregroundStyle(.secondary)
            if model.refreshing {
                ProgressView(value: Double(model.done), total: Double(max(1, model.total)))
            }
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.red)
                Button("Try again") { Task { await refresh() } }.frame(minHeight: 44)
            }
        }
        if (!didLoad || model.loading) && updates.isEmpty {
            ContentSkeleton(style: .results)
        } else if updates.isEmpty {
            empty(
                title: updatesSearch.isEmpty ? "No recent library updates" : "No matching updates",
                subtitle: updatesSearch.isEmpty
                    ? "Save titles to your Library, then check for updates."
                    : "Try another title or chapter.", symbol: "ArrowsClockwise")
        } else {
            // Missing source dates stay explicitly undated rather than being invented as today.
            ForEach(days(updates.map { $0.chapter.date ?? .distantPast }), id: \.self) { day in
                VStack(alignment: .leading, spacing: 28) {
                    dayHeading(day)
                    let items = updates.filter {
                        Calendar.current.isDate($0.chapter.date ?? .distantPast, inSameDayAs: day)
                    }
                    let titleIDs = items.map(\.mediaID).reduce(into: [String]()) {
                        if !$0.contains($1) { $0.append($1) }
                    }
                    ForEach(titleIDs, id: \.self) { id in
                        let bundle = items.filter { $0.mediaID == id }
                        let key = "update:\(day.timeIntervalSince1970):\(id)"
                        if let first = bundle.first {
                            HStack(spacing: 12) {
                                Button {
                                    toggle(key)
                                } label: {
                                    HStack(spacing: 16) {
                                        cover(
                                            first.entry.coverURL, symbol: first.entry.media.symbol)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(first.entry.title).font(.body.weight(.medium))
                                                .lineLimit(2)
                                            Text(
                                                "\(bundle.count) new \(first.entry.media == .anime ? (bundle.count == 1 ? "episode" : "episodes") : (bundle.count == 1 ? "chapter" : "chapters"))"
                                            )
                                            .font(.subheadline).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.contentShape(Rectangle())
                                }.accessibilityLabel("Expand \(first.entry.title) updates")
                                OverflowMenu {
                                    Button("View title") { open(first.entry, nil) }
                                    Button(
                                        expanded.contains(key) ? "Hide chapters" : "Show chapters"
                                    ) { toggle(key) }
                                    Button("Download chapters") {
                                        Task {
                                            for item in bundle
                                            where !item.chapter.downloaded
                                                && !model.queued.contains(item.id)
                                            {
                                                await model.act(on: item, delete: false)
                                            }
                                        }
                                    }.disabled(
                                        bundle.allSatisfy {
                                            $0.chapter.downloaded || model.queued.contains($0.id)
                                        })
                                } label: {
                                    PhosphorIcon("DotsThree").iconSize(22).foregroundStyle(
                                        NavigationStyle.accent
                                    )
                                    .frame(width: 44, height: 44)
                                }.accessibilityLabel("Actions for \(first.entry.title)")
                            }
                            if expanded.contains(key) {
                                ForEach(bundle) { updateRow($0) }.padding(.leading, 16)
                            }
                        } else {
                            ForEach(bundle) { updateRow($0) }
                        }
                    }
                }
            }
        }
    }

    private func updateRow(_ item: RecentUpdate) -> some View {
        HStack(spacing: 12) {
            Button {
                open(item.entry, nil)
            } label: {
                cover(item.entry.coverURL, symbol: item.entry.media.symbol)
            }.accessibilityLabel("View \(item.entry.title)")
            Button {
                open(item.entry, item.chapter.id)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.entry.title).font(.body.weight(.medium)).lineLimit(2)
                    Text(item.chapter.label).font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.accessibilityLabel("Open \(item.chapter.label)")
            Button {
                Task { await model.act(on: item, delete: item.chapter.downloaded) }
            } label: {
                Group {
                    if model.busy.contains(item.id) {
                        SkeletonBlock(width: 22, height: 22, radius: 6).skeletonMotion()
                    } else {
                        PhosphorIcon(
                            item.chapter.downloaded
                                ? "Trash"
                                : model.queued.contains(item.id) ? "Clock" : "DownloadSimple"
                        ).iconSize(21)
                    }
                }.frame(width: 44, height: 44)
            }.disabled(
                model.busy.contains(item.id)
                    || (model.queued.contains(item.id) && !item.chapter.downloaded)
            )
            .accessibilityLabel(
                item.chapter.downloaded
                    ? "Delete download"
                    : model.queued.contains(item.id)
                        ? "Download queued" : "Download \(item.chapter.label)")
        }.padding(.vertical, 4).opacity(item.chapter.completed ? 0.65 : 1)
    }

    private func cover(_ url: URL?, symbol: String) -> some View {
        CoverImage(url: url, symbol: symbol).frame(width: 52, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    private func empty(title: String, subtitle: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 280)
            .accessibilityIdentifier("recent.empty")
    }
    private func days(_ values: [Date]) -> [Date] {
        Set(values.map { Calendar.current.startOfDay(for: $0) }).sorted(by: >)
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

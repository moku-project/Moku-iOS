import SwiftUI

struct HistoryRow: View {
    let item: RecentHistoryTitle
    let expanded: Bool
    let opening: Bool
    let open: (String, String?) -> Void
    let toggle: () -> Void
    let showStatistics: () -> Void
    let clear: (RecentHistoryTitle) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    open(item.id, nil)
                } label: {
                    cover(item.entry.coverURL, symbol: "BookOpen")
                }.accessibilityLabel("View \(item.entry.title)")
                Button {
                    open(item.id, item.latest.chapterID)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.entry.title).font(.body.weight(.medium)).lineLimit(2)
                        Text(
                            "\(item.chapters.first?.title ?? "Chapter") · \(item.latest.completedUnits > 0 ? "Finished" : "Continue")"
                        )
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.disabled(opening).accessibilityLabel("Resume \(item.entry.title)")
                OverflowMenu {
                    Button("Resume") { open(item.id, item.latest.chapterID) }
                    Button("View title") { open(item.id, nil) }
                    Button(expanded ? "Hide chapters" : "Show chapters") { toggle() }
                    Button("Activity statistics") { showStatistics() }
                    Button("Clear title history", role: .destructive) {
                        clear(item)
                    }
                } label: {
                    PhosphorIcon("DotsThree").iconSize(22).foregroundStyle(NavigationStyle.accent)
                        .frame(width: 44, height: 44)
                }.accessibilityLabel("Actions for \(item.entry.title)")
            }
            if expanded {
                ForEach(item.chapters) { chapter in
                    Button {
                        open(item.id, chapter.id)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.title).font(.subheadline)
                                Text(
                                    "\(position(chapter.page, media: item.entry.media)) · \(duration(chapter.minutes)) · \(chapter.sessions.count) visit(s)"
                                )
                                .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            PhosphorIcon("BookOpen").foregroundStyle(.secondary)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.disabled(opening)
                }.padding(.leading, 16)
                Button("Clear title history", role: .destructive) {
                    clear(item)
                }.font(.caption).frame(minHeight: 44).padding(.leading, 16)
            }
        }.padding(.vertical, 4)

    }
    private func cover(_ url: URL?, symbol: String) -> some View {
        CoverImage(url: url, symbol: symbol).frame(width: 52, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    private func duration(_ minutes: Int) -> String {
        minutes < 1
            ? "< 1 min" : minutes < 60 ? "\(minutes) min" : "\(minutes / 60)h \(minutes % 60)m"
    }
    private func position(_ value: Int, media: String) -> String {
        media == "Anime"
            ? "\(value / 60):\(String(format: "%02d", value % 60))"
            : media == "Novels" ? "\(value)%" : "Page \(value)"
    }

}

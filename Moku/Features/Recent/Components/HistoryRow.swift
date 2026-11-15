import SwiftUI

/// One title in History: tap resumes, swipe clears, the context menu holds the rest; expanded, its chapters follow.
struct HistoryRow: View {
    let item: RecentHistoryTitle
    let expanded: Bool
    let opening: Bool
    let open: (String, String?) -> Void
    let toggle: () -> Void
    let showStatistics: () -> Void
    let clear: (RecentHistoryTitle) -> Void

    var body: some View {
        Button {
            open(item.id, item.latest.chapterID)
        } label: {
            HStack(spacing: 12) {
                CoverImage(url: item.entry.coverURL, symbol: "BookOpen").frame(width: 46, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.entry.title).font(.body.weight(.medium)).lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(
                        "\(item.chapters.first?.title ?? "Chapter") · \(item.latest.completedUnits > 0 ? "Finished" : "Continue")"
                    )
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(RecentFormat.timeAgo(item.latest.endedAt))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .disabled(opening)
        .accessibilityLabel("Resume \(item.entry.title)")
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing) {
            Button { clear(item) } label: {
                Label("Clear", systemImage: "trash")
            }.tint(.red)
        }
        .swipeActions(edge: .leading) {
            Button(action: toggle) {
                Label(expanded ? "Hide Chapters" : "Show Chapters", systemImage: "list.bullet")
            }.tint(.indigo)
        }
        .contextMenu {
            Button("Resume", systemImage: "play.fill") { open(item.id, item.latest.chapterID) }
            Button("View Title", systemImage: "info.circle") { open(item.id, nil) }
            Button(expanded ? "Hide Chapters" : "Show Chapters", systemImage: "list.bullet") { toggle() }
            Button("Activity Statistics", systemImage: "chart.bar") { showStatistics() }
            Divider()
            Button("Clear Title History", systemImage: "trash", role: .destructive) { clear(item) }
        }

        if expanded {
            ForEach(item.chapters) { chapter in
                Button {
                    open(item.id, chapter.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chapter.title).font(.subheadline).foregroundStyle(.primary)
                        Text(
                            "\(position(chapter.page, media: item.entry.media)) · \(RecentFormat.duration(chapter.minutes)) · \(chapter.sessions.count) visit(s)"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 58)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .disabled(opening)
                .listRowBackground(Color.clear)
            }
        }
    }

    private func position(_ value: Int, media: String) -> String {
        media == "Anime"
            ? "\(value / 60):\(String(format: "%02d", value % 60))"
            : media == "Novels" ? "\(value)%" : "Page \(value)"
    }
}

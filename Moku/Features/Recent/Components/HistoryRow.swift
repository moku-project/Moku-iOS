import SwiftUI

/// One title in History: tap resumes, swipe clears, the context menu holds the rest; expanded, its sessions follow.
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
            open(item.id, item.latest.endChapterID)
        } label: {
            HStack(spacing: 12) {
                CoverImage(url: item.entry.coverURL, symbol: "book").frame(
                    width: 46, height: 66
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.entry.title).font(.body.weight(.medium)).lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(HomeItem(entry: item.entry, session: item.latest).detail)
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
            Button {
                clear(item)
            } label: {
                Label("Clear", systemImage: "trash")
            }.tint(.red)
        }
        .swipeActions(edge: .leading) {
            Button(action: toggle) {
                Label(expanded ? "Hide Sessions" : "Show Sessions", systemImage: "list.bullet")
            }.tint(.indigo)
        }
        .contextMenu {
            Button("Resume", systemImage: "play.fill") { open(item.id, item.latest.endChapterID) }
            Button("View Title", systemImage: "info.circle") { open(item.id, nil) }
            Button(expanded ? "Hide Sessions" : "Show Sessions", systemImage: "list.bullet") {
                toggle()
            }
            Button("Activity Statistics", systemImage: "chart.bar") { showStatistics() }
            Divider()
            Button("Clear Title History", systemImage: "trash", role: .destructive) { clear(item) }
        }

        if expanded {
            ForEach(item.sessions) { session in
                Button {
                    open(item.id, session.endChapterID)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(HomeItem(entry: item.entry, session: session).detail)
                            .font(.subheadline).foregroundStyle(.primary)
                        Text(
                            "\(RecentFormat.timeAgo(session.endedAt)) · \(RecentFormat.duration(session.minutes)) · \(counted(session.chapters, item.entry.media == "Anime" ? "episode" : "chapter"))"
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
}

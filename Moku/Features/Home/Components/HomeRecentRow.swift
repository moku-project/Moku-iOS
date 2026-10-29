import SwiftUI

struct HomeRecentRow: View {
    let entry: HomeEntry
    let session: HomeSession
    var body: some View {
        HStack(spacing: 12) {
            HomeCover(url: entry.coverURL).frame(width: 42, height: 60).clipShape(
                RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title).font(.subheadline.weight(.medium)).lineLimit(2)
                Text((entry.chapters.first { $0.id == session.chapterID }?.displayTitle ?? "In progress")
                     + (entry.media == "Anime" ? "" : " · p.\(session.page)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(RecentFormat.timeAgo(session.endedAt)).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }.padding(.vertical, 10).contentShape(Rectangle())
    }
}

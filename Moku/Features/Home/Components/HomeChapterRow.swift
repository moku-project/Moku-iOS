import SwiftUI

struct HomeChapterRow: View {
    let chapter: HomeChapter
    var current = false
    var page: Int?
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(chapter.title).font(.subheadline.weight(.medium))
                Text(
                    current
                        ? "Page \(page ?? chapter.page) · In progress"
                        : chapter.isRead ? "Read" : "Next chapter"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            PhosphorIcon(current ? "Play.fill" : "CaretRight").foregroundStyle(
                current ? NavigationStyle.accent : .secondary)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(current ? NavigationStyle.accent.opacity(0.12) : .clear)
        .contentShape(Rectangle())
    }
}

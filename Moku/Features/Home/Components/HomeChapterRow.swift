import SwiftUI

struct HomeChapterRow: View {
    let chapter: HomeChapter
    var current = false
    var page: Int?
    var isAnime = false
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(chapter.displayTitle).font(.subheadline.weight(current ? .semibold : .medium))
                    .lineLimit(2).multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PhosphorIcon(current ? "Play.fill" : "CaretRight").foregroundStyle(
                current ? NavigationStyle.accent : .secondary)
                .frame(width: 20).accessibilityHidden(true)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(current ? NavigationStyle.accent.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
    private var position: String {
        let value = page ?? chapter.page
        return isAnime ? "\(value / 60):\(String(format: "%02d", value % 60))" : "p.\(value)"
    }

    private var subtitle: String? {
        if current { return "\(position) · in progress" }
        if chapter.isRead { return "Read" }
        return uploadLabel
    }

    private var uploadLabel: String? {
        guard let raw = chapter.uploadedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        var date = formatter.date(from: raw)
        if date == nil {
            formatter.formatOptions.insert(.withFractionalSeconds)
            date = formatter.date(from: raw)
        }
        return date?.formatted(.dateTime.month(.abbreviated).day())
    }
}

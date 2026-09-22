import SwiftUI

struct HomeHeroCard: View {
    let slot: HomeSlot
    let onResume: ((HomeEntry, HomeChapter) -> Void)?
    let onDetails: (HomeEntry) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let entry = slot.entry {
                    ScrollView(.vertical) {
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 16) {
                                cover(entry, width: 110)
                                    .frame(maxWidth: .infinity)
                                details(entry)
                            }
                            .padding(16)
                        } else {
                            HStack(alignment: .center, spacing: 16) {
                                cover(entry, width: min(180, (geometry.size.width - 32) * 0.36))
                                details(entry)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(16)
                            .frame(minHeight: geometry.size.height)
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ZStack {
                            Color.white.opacity(0.035)
                            PhosphorIcon("BookOpenText").iconSize(40)
                                .foregroundStyle(.gray.opacity(0.5))
                        }
                        .frame(maxHeight: .infinity)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Nothing here yet").font(.title3.weight(.medium)).foregroundStyle(
                                .secondary)
                            Text(
                                slot.id == 0
                                    ? "Read a title to see it here."
                                    : "Pin a title or keep reading to fill this slot."
                            )
                            .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .homePanel()
        }
    }

    private func cover(_ entry: HomeEntry, width: CGFloat) -> some View {
        HomeCover(url: entry.coverURL, contentMode: .fit)
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func details(_ entry: HomeEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    slot.isPinned
                        ? "Pinned" : entry.media == "Anime" ? "Watching" : "Reading"
                )
                .foregroundStyle(NavigationStyle.accent)
                if entry.unreadCount > 0 {
                    Text("\(entry.unreadCount) unread").foregroundStyle(.secondary)
                }
            }.font(.caption2.weight(.semibold))
            Text(entry.title).font(.headline).lineLimit(4)
            if let session = slot.session,
                let chapter = entry.chapters.first(where: { $0.id == session.chapterID }
                )
            {
                Text("\(chapter.title) · p.\(session.page)").font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.genres.isEmpty {
                Text(entry.genres.prefix(3).joined(separator: "  ·  ")).font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let session = slot.session,
                    let chapter = entry.chapters.first(where: {
                        $0.id == session.chapterID
                    })
                {
                    Button {
                        onResume?(entry, chapter)
                    } label: {
                        Label("Resume", phosphor: "Play.fill").font(
                            .subheadline.weight(.semibold)
                        )
                        .frame(maxWidth: .infinity).frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.black)
                    .background(
                        NavigationStyle.accent, in: RoundedRectangle(cornerRadius: 14)
                    )
                    .disabled(onResume == nil)
                    .accessibilityHint(
                        onResume == nil
                            ? "Reading is not available yet"
                            : "Continue from your saved position")
                } else {
                    Button("View title") { onDetails(entry) }.buttonStyle(
                        .borderedProminent
                    ).tint(NavigationStyle.accent)
                }
                Button {
                    onDetails(entry)
                } label: {
                    PhosphorIcon("Info").font(.title2).frame(
                        width: 44, height: 48)
                }
                .buttonStyle(.plain).accessibilityLabel("Title details")
            }
        }
    }
}

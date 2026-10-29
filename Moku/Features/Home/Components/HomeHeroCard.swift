import SwiftUI

struct HomeHeroCard: View {
    let slot: HomeSlot
    let onResume: ((HomeEntry, HomeChapter) -> Void)?
    let onDetails: (HomeEntry) -> Void
    var onLibrary: ((HomeEntry) -> Void)?
    @State private var summaryExpanded = false
    var onPin: () -> Void = {}
    var onUnpin: () -> Void = {}
    var onGenre: (String) -> Void = { _ in }
    var isOpening = false
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var onExpansionChange: (Bool) -> Void = { _ in }
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let entry = slot.entry {
                    Group {
                        VStack(alignment: .leading, spacing: 12) {
                            if typeSize.isAccessibilitySize {
                                cover(entry, width: 110)
                                    .frame(maxWidth: .infinity)
                                details(entry)
                            } else {
                                HStack(alignment: .top, spacing: 16) {
                                    cover(entry, width: min(150, geometry.size.width * 0.34))
                                    details(entry)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            if !entry.genres.isEmpty {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 12) { genreButtons(entry) }
                                    VStack(alignment: .leading, spacing: 0) { genreButtons(entry) }
                                }
                            }
                            if let summary = entry.summary, !summary.isEmpty {
                                Text(summary).font(.subheadline).foregroundStyle(.secondary)
                                    .lineLimit(summaryExpanded ? nil : 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("home.hero.summary")
                                Button(summaryExpanded ? "Show less" : "Read more") {
                                    summaryExpanded.toggle()
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NavigationStyle.accent)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("home.hero.readMore")
                            }
                            actions(entry)
                        }
                        .padding(.vertical, 4)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            onHeightChange($0)
                        }
                    }

                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ZStack {
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
                            if slot.id > 0 {
                                Button("Pin a title", action: onPin).frame(minHeight: 44)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .onChange(of: summaryExpanded) { _, expanded in onExpansionChange(expanded) }
            .onChange(of: slot.entry?.id) { _, _ in summaryExpanded = false }
        }
    }

    private func cover(_ entry: HomeEntry, width: CGFloat) -> some View {
        Button { onDetails(entry) } label: {
            HomeCover(url: entry.coverURL, contentMode: .fit, alignment: .top)
                .frame(width: width, height: width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityLabel("View \(entry.title)")
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
                    Text("\(entry.unreadCount) unread")
                        .foregroundStyle(.secondary)
                }
            }.font(.caption2.weight(.semibold))
            Text(entry.title).font(.headline).lineLimit(4)
            if let author = entry.author, !author.isEmpty {
                Text(author).font(.caption).foregroundStyle(.secondary)
            }
            if let session = slot.session,
                let chapter = entry.chapters.first(where: { $0.id == session.chapterID }
                )
            {
                Text(entry.media == "Anime"
                     ? "\(chapter.displayTitle) · \(session.page / 60):\(String(format: "%02d", session.page % 60))"
                     : "\(chapter.displayTitle) · p.\(session.page)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(RecentFormat.timeAgo(session.endedAt)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func actions(_ entry: HomeEntry) -> some View {
        HStack(spacing: 8) {
            if let onLibrary {
                Button { onLibrary(entry) } label: {
                    PhosphorIcon("Books", size: 22).frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("View in Library")
                .accessibilityIdentifier("home.hero.library")
                .disabled(isOpening)
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
                        Label(isOpening ? "Opening…" : "Resume", phosphor: "Play.fill").font(
                            .subheadline.weight(.semibold)
                        )
                        .frame(maxWidth: .infinity).frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.black)
                    .background(
                        NavigationStyle.accent, in: RoundedRectangle(cornerRadius: 14)
                    )
                    .disabled(onResume == nil || isOpening)
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
                    PhosphorIcon("Info", size: 22).frame(
                        width: 44, height: 48)
                }
                .buttonStyle(.plain).accessibilityLabel("Title details")
            }
            if slot.id > 0 {
                Button(slot.isPinned ? "Unpin" : "Pin", action: slot.isPinned ? onUnpin : onPin)
                    .font(.caption).frame(minHeight: 44)
            }
        }
    }

    private func genreButtons(_ entry: HomeEntry) -> some View {
        ForEach(Array(entry.genres.prefix(3)), id: \.self) { genre in
            Button(genre) { onGenre(genre) }
                .font(.caption).foregroundStyle(NavigationStyle.accent).frame(minHeight: 44)
        }
    }
}

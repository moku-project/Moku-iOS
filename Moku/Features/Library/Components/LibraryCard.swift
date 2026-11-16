import SwiftUI

struct LibraryCard: View {
    @AppStorage("preferences.showCardStats") private var showCardStats = true
    let item: LibraryItem
    let list: Bool
    let selected: Bool
    var compact = false
    var coversOnly = false

    var body: some View {
        Group {
            if list {
                HStack(spacing: 14) {
                    cover.frame(width: compact ? 40 : 72, height: compact ? 60 : 108)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).font(.subheadline.weight(.medium))
                        Text(item.media.title)
                            .font(.caption).foregroundStyle(.secondary)
                        if showCardStats && item.readUnits > 0 && !compact {
                            Text(progress).font(.caption).foregroundStyle(.secondary)
                        }
                        if showsProgress {
                            ProgressView(value: fraction)
                                .progressViewStyle(.linear)
                                .tint(NavigationStyle.accent)
                                .frame(maxWidth: 200)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                        if showCardStats && item.unread > 0 {
                            unreadBadge
                        }
                        HStack(spacing: 4) {
                            if item.chapterBookmarks > 0 && !compact {
                                Label("\(item.chapterBookmarks)", systemImage: "bookmark.fill")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .labelStyle(.titleAndIcon)
                            }
                            if item.tracked { trackedBadge }
                            if item.downloaded { downloadedBadge }
                        }
                    }

                }
                .padding(10).background(
                    NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    cover.aspectRatio(2 / 3, contentMode: .fit)
                    if !coversOnly {
                        Text(item.title).font(compact ? .caption : .subheadline).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilityStats)
    }

    /// A started title with a known chapter count.
    private var showsProgress: Bool {
        showCardStats && item.readUnits > 0 && item.totalUnits > 0
    }

    private var fraction: Double {
        guard item.totalUnits > 0 else { return 0 }
        return min(1, Double(item.readUnits) / Double(item.totalUnits))
    }

    private var unreadBadge: some View {
        Text(item.unread, format: .number)
            .font((compact ? Font.caption2 : .caption).weight(.semibold).monospacedDigit())
            .foregroundStyle(.black)
            .padding(.horizontal, compact ? 5 : 7).padding(.vertical, 2)
            .background(NavigationStyle.accent, in: Capsule())
    }

    private var downloadedBadge: some View {
        Image(systemName: "arrow.down.circle.fill")
            .font(compact ? .caption : .subheadline)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, NavigationStyle.accent)
    }

    private var trackedBadge: some View {
        Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
            .font(compact ? .caption : .subheadline)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, NavigationStyle.accent)
    }

    private var accessibilityStats: String {
        var parts: [String] = []
        if showCardStats && item.totalUnits > 0 && item.readUnits > 0 {
            parts.append(
                "\(item.readUnits) of \(item.totalUnits) \(item.media == .anime ? "watched" : "read")"
            )
        }
        if showCardStats && item.unread > 0 { parts.append("\(item.unread) unread") }
        if item.downloaded { parts.append("Downloaded") }
        if item.tracked { parts.append("Tracked") }
        if item.chapterBookmarks > 0 {
            parts.append(
                "\(item.chapterBookmarks) bookmarked \(item.chapterBookmarks == 1 ? "chapter" : "chapters")"
            )
        }
        return parts.joined(separator: ", ")
    }

    private var progress: String {
        "\(item.media == .anime ? "Watching" : "Reading") · \(item.readUnits)/\(item.totalUnits)"
    }

    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = item.coverURL {
                CoverImage(url: url, symbol: item.media.symbol)
            } else {
                artwork
            }
            if !list {
                VStack(spacing: 0) {
                    if showCardStats && item.readUnits > 0 && !compact && !coversOnly {
                        Text(progress).font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.black.opacity(0.65))
                    }
                    if showsProgress {
                        // Thin read/total bar along the bottom edge of the cover.
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.55))
                                Rectangle().fill(NavigationStyle.accent)
                                    .frame(width: geometry.size.width * fraction)
                            }
                        }
                        .frame(height: 3)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if !list && showCardStats && item.unread > 0 {
                unreadBadge.padding(compact ? 4 : 6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !list && (item.downloaded || item.tracked) {
                HStack(spacing: 3) {
                    if item.tracked { trackedBadge }
                    if item.downloaded { downloadedBadge }
                }
                .shadow(color: .black.opacity(0.4), radius: 2)
                .padding(compact ? 4 : 6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    selected ? NavigationStyle.accent : .white.opacity(0.1),
                    lineWidth: selected ? 2 : 0.5)
        }
    }

    /// Placeholder book-jacket artwork drawn natively; no media-type badges on covers.
    private var artwork: some View {
        GeometryReader { geometry in
            let colors: [Color] = [.indigo, .brown, .teal, .purple, .blue, .orange]
            let index = Int(item.id.split(separator: "-").last ?? "0") ?? 0
            let tint = colors[abs(index % colors.count)]
            ZStack {
                LinearGradient(
                    colors: [tint.opacity(0.55), Color(white: 0.07)], startPoint: .topLeading,
                    endPoint: .bottomTrailing)
                Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    .frame(width: geometry.size.width * 0.95)
                    .offset(x: geometry.size.width * 0.3, y: -geometry.size.height * 0.2)
                Circle().fill(tint.opacity(0.3))
                    .frame(width: geometry.size.width * 0.8)
                    .blur(radius: 15).offset(x: -30, y: 30)
                VStack(alignment: .leading, spacing: 10) {
                    Rectangle().fill(.white.opacity(0.3)).frame(width: 24, height: 1)
                    Spacer()
                    Text(item.title).font(.system(.title3).weight(.medium))
                        .foregroundStyle(.white.opacity(0.85)).minimumScaleFactor(0.75)
                    Rectangle().fill(.white.opacity(0.3)).frame(width: 24, height: 1)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }
}

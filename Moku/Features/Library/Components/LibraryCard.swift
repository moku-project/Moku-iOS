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
                    }
                    Spacer(minLength: 0)

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
            if showCardStats && item.readUnits > 0 && !compact {
                Text(progress).font(.caption2.weight(.medium))
                    .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.65))
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

    /// Temporary book-jacket artwork is native drawing, never downloaded media or
    /// fake saved content. No media-type badges are placed on the covers.
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

import SwiftUI

struct ExtensionIdentity: View {
    let item: SourceExtension
    @ScaledMetric(relativeTo: .body) private var logoSize = 44

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: logoSize, height: logoSize)
                .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.225, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: logoSize * 0.225, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    .lineLimit(2)
                Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                if let badge {
                    Text(badge).font(.caption).foregroundStyle(item.isNsfw ? .orange : .secondary)
                }
            }
        }
    }

    @ViewBuilder private var icon: some View {
        if item.iconURL != nil {
            CoverImage(url: item.iconURL, symbol: "PuzzlePiece", isIcon: true, bareIcon: true)
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        NavigationStyle.accent.opacity(0.35), NavigationStyle.accent.opacity(0.15),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: logoSize * 0.46))
                    .foregroundStyle(NavigationStyle.accent)
            }
        }
    }

    private var badge: String? {
        var parts: [String] = []
        if item.isNsfw { parts.append("18+") }
        if item.installed && !item.enabled { parts.append("Disabled") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

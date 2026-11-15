import SwiftUI

struct ExtensionIdentity: View {
    let item: SourceExtension
    @ScaledMetric(relativeTo: .body) private var logoSize = 44

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: item.iconURL, symbol: "PuzzlePiece", isIcon: true, bareIcon: true)
                .frame(width: logoSize, height: logoSize)
                .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.22, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).foregroundStyle(.primary).lineLimit(2)
                Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                if let badge {
                    Text(badge).font(.caption).foregroundStyle(item.isNsfw ? .orange : .secondary)
                }
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

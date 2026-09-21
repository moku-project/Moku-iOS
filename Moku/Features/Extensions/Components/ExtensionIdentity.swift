import SwiftUI

struct ExtensionIdentity: View {
    let item: SourceExtension
    @ScaledMetric(relativeTo: .body) private var logoSize = 64
    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: item.iconURL, symbol: "PuzzlePiece", isIcon: true, bareIcon: true)
                .frame(width: logoSize, height: logoSize)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayName).font(.body.weight(.medium)).lineLimit(2)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 8) {
                    if item.isNsfw { Text("18+").foregroundStyle(.orange) }
                    if item.needsUpdate == true {
                        Text("Update available").foregroundStyle(NavigationStyle.accent)
                    } else if item.installed {
                        Text(item.enabled ? "Installed" : "Disabled").foregroundStyle(.secondary)
                    }
                }.font(.caption2)
            }
        }
    }
}

extension View {
    func managementListStyle() -> some View {
        self.listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
            .background(NavigationStyle.background)
    }
}

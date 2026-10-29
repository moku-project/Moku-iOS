import SwiftUI

struct MoreIndexView: View {
    @ScaledMetric(relativeTo: .body) private var rowTextSize = 17.5

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(MoreDestination.allCases) { destination in
                    NavigationLink(value: destination) {
                        HStack(spacing: 8) {
                            PhosphorIcon(destination.symbol, size: 21.25)
                                .foregroundStyle(.secondary).frame(minWidth: 30)
                            Text(destination.rawValue).font(.system(size: rowTextSize))
                            Spacer(minLength: 12)
                            PhosphorIcon("CaretRight").iconSize(13.75)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 64).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("more.category.\(destination.rawValue)")
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .tracksNavigationScroll()
        .accessibilityIdentifier("more.index")
    }
}

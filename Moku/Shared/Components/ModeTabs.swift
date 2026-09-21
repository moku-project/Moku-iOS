import SwiftUI

struct ModeTabs: View {
    @Binding var mode: ContentMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("preferences.animations") private var animations = true
    @State private var widths: [ContentMode: CGFloat] = [:]
    var prefix = "recent"
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ContentMode.allCases) { choice in
                Button {
                    mode = choice
                } label: {
                    Text(choice.title).font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(mode == choice ? 0.92 : 0.45))
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.width
                        } action: {
                            widths[choice] = $0
                        }
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("\(prefix).mode.\(choice.rawValue)")
                    .accessibilityAddTraits(mode == choice ? .isSelected : [])
            }
        }.overlay(alignment: .bottom) {
            GeometryReader { geometry in
                let width = geometry.size.width / CGFloat(ContentMode.allCases.count)
                let index = ContentMode.allCases.firstIndex(of: mode) ?? 0
                let indicator = (widths[mode] ?? 44) + 12
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(.white.opacity(0.14)).frame(height: 0.5)
                    Capsule().fill(NavigationStyle.accent).frame(width: indicator, height: 2)
                        .offset(x: CGFloat(index) * width + (width - indicator) / 2)
                        .animation(
                            reduceMotion || !animations ? nil : .easeInOut(duration: 0.28),
                            value: mode)
                }
            }.frame(height: 2).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

/// A bounded popup with a scrolling body and permanently reachable actions.

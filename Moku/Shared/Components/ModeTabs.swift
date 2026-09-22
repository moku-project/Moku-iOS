import SwiftUI

/// Shared, centered media tabs for page headers and filters.
struct ModeTabs: View {
    @Binding var mode: ContentMode
    var prefix = "recent"
    var onSelect: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("preferences.animations") private var animations = true
    @Namespace private var tabsSpace
    @State private var modeLabelFrames: [ContentMode: CGRect] = [:]
    private var reduceMotion: Bool { systemReduceMotion || !animations }

    var body: some View {
        let coordinateSpace = tabsSpace
        HStack(spacing: 8) {
            ForEach(ContentMode.allCases) { choice in
                Button {
                    mode = choice
                    onSelect()
                } label: {
                    Text(choice.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(mode == choice ? 0.92 : 0.45))
                        .lineLimit(1)
                        .onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .named(coordinateSpace))
                        } action: { frame in
                            modeLabelFrames[choice] = frame
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())

                }
                .buttonStyle(ModeTabButtonStyle())
                .accessibilityIdentifier("\(prefix).mode.\(choice.rawValue)")
                .accessibilityAddTraits(mode == choice ? .isSelected : [])
            }
        }
        .padding(.horizontal, NavigationStyle.pagePadding)
        .frame(maxWidth: .infinity, alignment: .center)
        .coordinateSpace(name: tabsSpace)
        .overlay(alignment: .bottom) {
            GeometryReader { _ in
                let labelFrame = modeLabelFrames[mode] ?? .zero
                let indicatorWidth = labelFrame.width + 12
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(.white.opacity(0.14)).frame(height: 0.5)
                    Capsule().fill(NavigationStyle.accent)
                        .frame(width: indicatorWidth, height: 2)
                        .offset(x: labelFrame.midX - indicatorWidth / 2)
                        .opacity(labelFrame.isEmpty ? 0 : 1)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: mode)
                }
            }
            .frame(height: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

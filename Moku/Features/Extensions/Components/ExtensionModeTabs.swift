import SwiftUI

struct ExtensionModeTabs: View {
    let model: ExtensionsViewModel
    let reduceMotion: Bool
    let dismissTools: () -> Void
    @State private var modeLabelWidths: [ContentMode: CGFloat] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ContentMode.allCases) { choice in
                Button {
                    model.media = choice
                    dismissTools()
                } label: {
                    Text(choice.title).font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(model.media == choice ? 0.92 : 0.45))
                        .lineLimit(1)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.width
                        } action: { width in
                            modeLabelWidths[choice] = width
                        }
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("extensions.mode.\(choice.rawValue)")
                .accessibilityAddTraits(model.media == choice ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) {
            GeometryReader { geometry in
                let width = geometry.size.width / CGFloat(ContentMode.allCases.count)
                let index = ContentMode.allCases.firstIndex(of: model.media) ?? 0
                let indicatorWidth = (modeLabelWidths[model.media] ?? 44) + 12
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(.white.opacity(0.14)).frame(height: 0.5)
                    Capsule().fill(NavigationStyle.accent).frame(width: indicatorWidth, height: 2)
                        .offset(x: CGFloat(index) * width + (width - indicatorWidth) / 2)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.28), value: model.media)
                }
            }.frame(height: 2).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

}

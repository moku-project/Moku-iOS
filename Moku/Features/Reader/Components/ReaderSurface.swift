import SwiftUI

struct ReaderSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("preferences.solidSurfaces") private var solid = false
    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: 10)
            if reduceTransparency || solid {
                shape.fill(Color(white: 0.05))
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(Color(white: 0.025).opacity(0.90)) }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
    }
}

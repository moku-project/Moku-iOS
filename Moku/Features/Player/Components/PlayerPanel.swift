import SwiftUI

private struct PlayerPanel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8).fill(
                        Color(white: 0.04).opacity(reduceTransparency ? 1 : 0.82)))
        }.overlay(
            RoundedRectangle(cornerRadius: 8).strokeBorder(
                Color.white.opacity(0.16), lineWidth: 0.5
            ).allowsHitTesting(false))
    }
}
extension View { func playerPanel() -> some View { modifier(PlayerPanel()) } }

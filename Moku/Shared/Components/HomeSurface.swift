import SwiftUI

extension View {
    func homePanel() -> some View {
        background(NavigationStyle.surface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(
                    .white.opacity(0.08), lineWidth: 0.5)
            }
    }
}

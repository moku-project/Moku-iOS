import Observation
import SwiftUI

@MainActor @Observable
final class AppTheme {
    static let shared = AppTheme()
    var name = "midnight"
    var palette = NativeTheme.builtins[0]
}

enum NavigationStyle {
    static let pagePadding: CGFloat = 10
    static let navigationHeight: CGFloat = 52
    static let navigationCornerRadius: CGFloat = 26
    static let navigationHorizontalPadding: CGFloat = 8
    static let navigationSpacing: CGFloat = 2
    static let navigationBottomPadding: CGFloat = 0
    static let navigationInset = navigationHeight + navigationSpacing
    static let navigationLowering: CGFloat = 12
    static let compactNavigationHeight: CGFloat = 46
    static let navigationIndicatorSpacing: CGFloat = 2

    @MainActor static var background: Color { Color(themeHex: AppTheme.shared.palette.background) }
    @MainActor static var surface: Color { Color(themeHex: AppTheme.shared.palette.surface) }
    @MainActor static var accent: Color { Color(themeHex: AppTheme.shared.palette.accent) }

}

struct FloatingSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("preferences.solidSurfaces") private var solidSurfaces = false
    let cornerRadius: CGFloat
    var tintOpacity: Double = 0.55

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                if reduceTransparency || solidSurfaces {
                    shape.fill(NavigationStyle.surface)
                } else {
                    shape.fill(.ultraThinMaterial)
                        .overlay { shape.fill(NavigationStyle.surface.opacity(tintOpacity)) }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

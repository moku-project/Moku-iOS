import Observation
import SwiftUI

@MainActor @Observable
final class AppTheme {
    static let shared = AppTheme()
    var name = "midnight"
    var palette = NativeTheme.builtins[0] { didSet { if palette != oldValue { colors = Colors(palette) } } }
    /// Parsed once per palette change; every view reads these many times per frame.
    private(set) var colors = Colors(NativeTheme.builtins[0])

    struct Colors {
        let background, surface, accent, border, muted, secondary, text: Color
        init(_ palette: NativeTheme) {
            background = Color(themeHex: palette.background)
            surface = Color(themeHex: palette.surface)
            accent = Color(themeHex: palette.accent)
            border = Color(themeHex: palette.border)
            muted = Color(themeHex: palette.muted)
            secondary = Color(themeHex: palette.secondary)
            text = Color(themeHex: palette.text)
        }
    }
}

enum NavigationStyle {
    static let selectionAnimation = Animation.easeInOut(duration: 0.28)
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

    @MainActor static var background: Color { AppTheme.shared.colors.background }
    @MainActor static var surface: Color { AppTheme.shared.colors.surface }
    @MainActor static var accent: Color { AppTheme.shared.colors.accent }

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

extension View {
    /// Sheets and popups follow the app theme instead of forcing dark, so the
    /// light themes don't show dark panels with light text.
    func themedColorScheme() -> some View {
        modifier(ThemedColorScheme())
    }
}

private struct ThemedColorScheme: ViewModifier {
    func body(content: Content) -> some View {
        content.preferredColorScheme(AppTheme.shared.palette.isLight ? .light : .dark)
    }
}

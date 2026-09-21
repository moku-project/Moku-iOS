import Observation
import SwiftUI

@MainActor @Observable
final class AppTheme {
    static let shared = AppTheme()
    var name = "midnight"
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

    @MainActor static var background: Color {
        switch AppTheme.shared.name {
        case "charcoal": Color(white: 0.10)
        case "sepia": Color(red: 0.10, green: 0.085, blue: 0.06)
        default: Color(white: 8 / 255)
        }
    }
    @MainActor static var surface: Color {
        switch AppTheme.shared.name {
        case "charcoal": Color(white: 0.15)
        case "sepia": Color(red: 0.15, green: 0.13, blue: 0.095)
        default: Color(white: 23 / 255)
        }
    }
    @MainActor static var accent: Color {
        switch AppTheme.shared.name {
        case "charcoal": Color(red: 0.55, green: 0.70, blue: 0.86)
        case "sepia": Color(red: 0.82, green: 0.65, blue: 0.36)
        default: Color(red: 122 / 255, green: 170 / 255, blue: 122 / 255)
        }
    }
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

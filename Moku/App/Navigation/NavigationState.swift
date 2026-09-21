import SwiftUI

/// Accumulate directional travel to avoid reacting to finger jitter or bounce.
struct NavigationState {
    private(set) var isCompact = false
    private var travel: CGFloat = 0

    mutating func update(from old: CGFloat, to new: CGFloat) {
        guard new > 8 else {
            isCompact = false
            travel = 0
            return
        }
        let delta = new - old
        guard delta != 0 else { return }
        if (delta > 0) != (travel > 0) { travel = 0 }
        travel += delta
        if travel >= 24 {
            isCompact = true
            travel = 0
        } else if travel <= -12 {
            isCompact = false
            travel = 0
        }
    }
}

extension EnvironmentValues {
    @Entry var navigationContentBottomInset: CGFloat = 0
    @Entry var navigationContentSafeAreaAdjustment: CGFloat = 0
    @Entry var navigationIndicatorBottomInset: CGFloat = 0
    @Entry var navigationScrollChanged: @MainActor (CGFloat, CGFloat) -> Void = { _, _ in }
}

private struct NavigationScrollTracking: ViewModifier {
    @Environment(\.navigationScrollChanged) private var changed
    @Environment(\.navigationContentBottomInset) private var contentInset
    @Environment(\.navigationIndicatorBottomInset) private var indicatorInset
    @Environment(\.navigationContentSafeAreaAdjustment) private var safeAreaAdjustment

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, max(0, contentInset - safeAreaAdjustment), for: .scrollContent)
            .contentMargins(.bottom, indicatorInset, for: .scrollIndicators)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let maximum = max(
                    0,
                    geometry.contentSize.height + geometry.contentInsets.top
                        + geometry.contentInsets.bottom - geometry.containerSize.height)
                // Clamp rubber-banding so bottom bounce does not expand the bar.
                return min(maximum, max(0, geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { old, new in
                changed(old, new)
            }
    }
}

extension View {
    func tracksNavigationScroll() -> some View { modifier(NavigationScrollTracking()) }
}

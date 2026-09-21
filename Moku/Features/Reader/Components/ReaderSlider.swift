import SwiftUI

/// Desktop's thin sage track and round thumb with a 44-point native touch target.
struct ReaderSlider: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let step: Double
    @Environment(\.layoutDirection) private var direction
    @Environment(\.isEnabled) private var enabled
    init(value: Binding<Double>, in bounds: ClosedRange<Double>, step: Double = 1) {
        _value = value
        self.bounds = bounds
        self.step = step
    }
    private var fraction: Double {
        min(
            1,
            max(0, (value - bounds.lowerBound) / max(0.001, bounds.upperBound - bounds.lowerBound)))
    }
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 16)
            let position = width * (direction == .rightToLeft ? 1 - fraction : fraction)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: 3)
                Capsule().fill(NavigationStyle.accent)
                    .frame(width: width * fraction, height: 3)
                    .offset(x: direction == .rightToLeft ? width * (1 - fraction) : 0)
                Circle().fill(NavigationStyle.accent).frame(width: 14, height: 14)
                    .offset(x: position - 7)
            }.padding(.horizontal, 8).frame(height: 44).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { gesture in
                        guard enabled else { return }
                        var f = min(1, max(0, (gesture.location.x - 8) / width))
                        if direction == .rightToLeft { f = 1 - f }
                        set(bounds.lowerBound + f * (bounds.upperBound - bounds.lowerBound))
                    })
        }.frame(height: 44).opacity(enabled ? 1 : 0.4)
            .accessibilityElement().accessibilityValue(value.formatted())
            .accessibilityAdjustableAction { adjustment in
                guard enabled else { return }
                switch adjustment {
                case .increment: set(value + step)
                case .decrement: set(value - step)
                @unknown default: break
                }
            }
    }
    private func set(_ next: Double) {
        value = min(
            bounds.upperBound,
            max(
                bounds.lowerBound,
                bounds.lowerBound + ((next - bounds.lowerBound) / step).rounded() * step))
    }
}

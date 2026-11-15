import SwiftUI
import UIKit

struct PlayerTimeline: UIViewRepresentable {
    let value: Double
    let duration: Double
    let changed: (Double) -> Void
    let editing: (Bool) -> Void

    func makeUIView(context: Context) -> UISlider {
        let slider = PlayerSlider()
        let fill = UIColor.white
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { _ in
            fill.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 12, height: 12)).fill()
        }
        slider.setThumbImage(thumb, for: .normal)
        slider.setThumbImage(thumb, for: .highlighted)
        for (color, minimum) in [(fill, true), (UIColor(white: 1, alpha: 0.3), false)] {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 3)).image { _ in
                color.setFill()
                UIBezierPath(
                    roundedRect: CGRect(x: 0, y: 0, width: 3, height: 3), cornerRadius: 1.5
                ).fill()
            }.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1))
            if minimum {
                slider.setMinimumTrackImage(image, for: .normal)
            } else {
                slider.setMaximumTrackImage(image, for: .normal)
            }
        }
        slider.accessibilityLabel = "Playback position"
        slider.accessibilityIdentifier = "player.timeline"
        slider.addTarget(
            context.coordinator, action: #selector(Coordinator.begin(_:)), for: .touchDown)
        slider.addTarget(
            context.coordinator, action: #selector(Coordinator.change(_:)), for: .valueChanged)
        slider.addTarget(
            context.coordinator, action: #selector(Coordinator.end(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return slider
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISlider, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: 44)
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.parent = self
        let total = duration.isFinite ? min(Double(Int32.max), max(0, duration)) : 0
        slider.maximumValue = Float(max(1, total))
        slider.isEnabled = total > 0
        if !slider.isTracking {
            slider.value = Float(value.isFinite ? min(total, max(0, value)) : 0)
        }
        slider.accessibilityValue =
            "\(PlayerViewModel.time(value)) of \(PlayerViewModel.time(duration))"
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    @MainActor final class Coordinator: NSObject {
        var parent: PlayerTimeline
        init(_ parent: PlayerTimeline) { self.parent = parent }
        @objc func begin(_ slider: UISlider) {
            parent.editing(true)
            parent.changed(Double(slider.value))
        }
        @objc func change(_ slider: UISlider) {
            parent.changed(Double(slider.value))
            if !slider.isTracking { parent.editing(false) }
        }
        @objc func end(_ slider: UISlider) {
            parent.changed(Double(slider.value))
            parent.editing(false)
        }
    }
}

/// Accepts a touch anywhere on the track, since playback may move the small thumb while the user reaches for it.
private final class PlayerSlider: UISlider {
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        updatePosition(touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updatePosition(touch)
        sendActions(for: .valueChanged)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch { updatePosition(touch) }
    }

    private func updatePosition(_ touch: UITouch) {
        let track = trackRect(forBounds: bounds)
        let start = thumbRect(forBounds: bounds, trackRect: track, value: minimumValue).midX
        let end = thumbRect(forBounds: bounds, trackRect: track, value: maximumValue).midX
        guard end != start else { return }
        let fraction = min(1, max(0, (touch.location(in: self).x - start) / (end - start)))
        value = minimumValue + Float(fraction) * (maximumValue - minimumValue)
    }
}

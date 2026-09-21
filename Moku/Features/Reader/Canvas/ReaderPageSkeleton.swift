import UIKit

/// Page-sized native placeholder; animate only the visible image requests.
final class ReaderPageSkeleton: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.12, alpha: 1)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setAnimating(_ animate: Bool) {
        guard animate && !UIAccessibility.isReduceMotionEnabled else {
            layer.removeAnimation(forKey: "skeleton")
            return
        }
        guard layer.animation(forKey: "skeleton") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.4
        pulse.duration = SkeletonTiming.halfCycle
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        layer.add(pulse, forKey: "skeleton")
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { layer.removeAnimation(forKey: "skeleton") }
    }
}

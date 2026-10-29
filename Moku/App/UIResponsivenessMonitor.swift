import Foundation

#if DEBUG
    import OSLog
#endif

#if DEBUG
    /// Measures a background-to-main hop, not service/network duration. Keep this
    /// enabled in development so on-device stalls have an actionable console signal.
    @MainActor final class UIResponsivenessMonitor {
        static let shared = UIResponsivenessMonitor()
        private static let logger = Logger(subsystem: "com.moku.app", category: "UIResponsiveness")
        private var sampling: Task<Void, Never>?

        func setActive(_ active: Bool) {
            sampling?.cancel()
            sampling = nil
            guard active else { return }
            sampling = Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    let queued = ContinuousClock.now
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        let duration = queued.duration(to: .now)
                        if duration > .milliseconds(250) {
                            let parts = duration.components
                            let milliseconds =
                                parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000
                            Self.logger.warning("Main actor response delayed by \(milliseconds) ms")
                        }
                    }
                }
            }
        }
    }
#endif

#if DEBUG
import SwiftUI
import UIKit

/// In-app timing excludes XCTest's tap/idle overhead. Two display ticks allow the
/// selection transaction to be presented before recording the next frame.
@MainActor enum NavigationTiming {
    private static let logger = Logger(subsystem: "com.moku.app", category: "Navigation")
    static var pending: (tab: AppTab, started: CFTimeInterval)?
    static func begin(_ tab: AppTab) { pending = (tab, CACurrentMediaTime()) }
    static func finish(tab: AppTab, started: CFTimeInterval) -> Int {
        let milliseconds = Int((CACurrentMediaTime() - started) * 1_000)
        if milliseconds >= 100 {
            logger.warning("Tab \(tab.rawValue, privacy: .public) presented after \(milliseconds) ms")
        } else {
            logger.debug("Tab \(tab.rawValue, privacy: .public) presented after \(milliseconds) ms")
        }
        if pending?.started == started { pending = nil }
        return milliseconds
    }
}

struct NavigationFrameProbe: UIViewRepresentable {
    let tab: AppTab
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isAccessibilityElement = ProcessInfo.processInfo.arguments.contains("--ui-testing-navigation-timing")
        view.accessibilityIdentifier = "navigation.frameLatency"
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: Probe, context: Context) { view.observe(tab) }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.link?.invalidate() }

    final class Probe: UIView {
        var link: CADisplayLink?
        var request: (tab: AppTab, started: CFTimeInterval)?
        var frames = 0
        func observe(_ tab: AppTab) {
            guard let pending = NavigationTiming.pending, pending.tab == tab,
                request?.started != pending.started else { return }
            link?.invalidate()
            request = pending
            frames = 0
            let next = CADisplayLink(target: self, selector: #selector(displayTick))
            link = next
            next.add(to: .main, forMode: .common)
        }
        @objc func displayTick() {
            frames += 1
            guard frames >= 2, let request else { return }
            let milliseconds = NavigationTiming.finish(tab: request.tab, started: request.started)
            accessibilityValue = "\(request.tab.rawValue):\(milliseconds)"
            link?.invalidate()
            link = nil
        }
    }
}
#endif

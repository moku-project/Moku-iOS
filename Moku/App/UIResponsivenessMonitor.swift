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

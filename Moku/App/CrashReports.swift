import MetricKit
import Observation
import UIKit

/// Notices that the last session ended in a crash and offers a bug report.
@MainActor @Observable final class CrashReports: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReports()
    private static let runningKey = "session.running"
    /// Set when the previous session crashed; cleared once the prompt is dismissed.
    var pending = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var prompted = false

    private static var disabled: Bool {
        PreviewMode.isEnabled || PreviewMode.isUnitTestHost
            || ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--ui-testing") || $0 == "--acceptance" }
    }

    /// Call once at launch: a marker still set from last time means it never reached the background.
    func start() {
        guard !started, !Self.disabled else { return }
        started = true
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.runningKey) { prompt() }
        defaults.set(true, forKey: Self.runningKey)
        let center = NotificationCenter.default
        for (name, running) in [
            (UIApplication.didEnterBackgroundNotification, false),
            (UIApplication.willTerminateNotification, false),
            (UIApplication.willEnterForegroundNotification, true),
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                UserDefaults.standard.set(running, forKey: Self.runningKey)
            }
        }
        MXMetricManager.shared.add(self)
    }

    private func prompt() {
        guard !prompted else { return }
        prompted = true
        pending = true
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard payloads.contains(where: { !($0.crashDiagnostics ?? []).isEmpty }) else { return }
        Task { @MainActor in CrashReports.shared.prompt() }
    }
}

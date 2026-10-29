import Observation
import SwiftUI
import UIKit

/// Desktop Toaster counterpart: short, non-blocking confirmations and failures.
/// Toasts render in their own pass-through window so they stay visible above the
/// reader, the player and sheets without taking touches from them.
@MainActor @Observable final class Toaster {
    enum Kind: Sendable { case success, error, info, download }
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let kind: Kind
        let title: String
        let detail: String?
    }

    static let shared = Toaster()
    private(set) var toasts: [Toast] = []
    private var window: UIWindow?

    func show(_ title: String, detail: String? = nil, kind: Kind = .success, duration: Duration = .seconds(3.5)) {
        let toast = Toast(kind: kind, title: title, detail: detail)
        // Match desktop: at most a few on screen, newest last.
        toasts = Array((toasts.filter { $0.title != title } + [toast]).suffix(3))
        attach()
        UIAccessibility.post(notification: .announcement, argument: detail.map { "\(title). \($0)" } ?? title)
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            self?.dismiss(toast.id)
        }
    }

    func dismiss(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    private func attach() {
        guard window == nil,
            let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .alert
        let host = UIHostingController(rootView: ToastStack(toaster: self))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }
}

/// Only the toast cards take touches; everything else falls through to the app.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === rootViewController?.view ? nil : view
    }
}

private struct ToastStack: View {
    let toaster: Toaster
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toaster.toasts) { toast in
                ToastCard(toast: toast)
                    .onTapGesture { toaster.dismiss(toast.id) }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: toaster.toasts)
    }
}

private struct ToastCard: View {
    let toast: Toaster.Toast

    private var icon: String {
        switch toast.kind {
        case .success: "CheckCircle.fill"
        case .error: "WarningCircle.fill"
        case .info: "Info.fill"
        case .download: "DownloadSimple.fill"
        }
    }

    private var tint: Color {
        switch toast.kind {
        case .error: Color(red: 0.94, green: 0.36, blue: 0.36)
        default: NavigationStyle.accent
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            PhosphorIcon(icon).foregroundStyle(tint).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.subheadline.weight(.semibold))
                if let detail = toast.detail {
                    Text(detail).font(.caption).foregroundStyle(GeneralStyle.label).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(GeneralStyle.text)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .modifier(FloatingSurface(cornerRadius: 14, tintOpacity: 0.8))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap to dismiss")
        .accessibilityIdentifier("toast")
    }
}

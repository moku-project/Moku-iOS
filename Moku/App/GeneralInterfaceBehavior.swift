import Observation
import SwiftUI
import UIKit

/// Scales layout proposals as well as artwork, so larger controls remain scrollable.
/// Reader/player full-screen presentations keep their independent sizing.
extension Notification.Name { static let mokuPreviewIdle = Notification.Name("moku.previewIdle") }

struct GeneralInterfaceBehavior: ViewModifier {
    @AppStorage("preferences.interfaceScale") private var percentage = 100.0
    @AppStorage("preferences.idleTimeout") private var idleMinutes = 5
    @Environment(\.scenePhase) private var scenePhase
    @State private var idle = IdleScreenState()
    @State private var mediaPresented = false

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let scale = mediaPresented ? 1 : GeneralPreferences.clampedScale(percentage) / 100
            content
                .frame(width: geometry.size.width / scale, height: geometry.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: geometry.size.width, height: geometry.size.height, alignment: .topLeading
                )
        }
        .background {
            if idleMinutes > 0 && scenePhase == .active {
                IdleActivityObserver(
                    activity: { if !idle.isVisible { idle.recordActivity() } },
                    blocked: idle.setPresentationBlocked
                )
                .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .overlay {
            if idle.isVisible {
                Button {
                    idle.recordActivity()
                } label: {
                    VStack(spacing: 16) {
                        Text("Moku").font(.largeTitle.weight(.light))
                        Text("Tap to continue").font(.footnote).foregroundStyle(.secondary)
                    }.foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(NavigationStyle.background.ignoresSafeArea())
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Moku idle screen. Tap to continue")
                    .accessibilityIdentifier("general.idleScreen")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mokuPreviewIdle)) { _ in idle.preview() }
        .onPreferenceChange(GeneralMediaPresentedKey.self) { presented in
            mediaPresented = presented
            idle.setMediaActive(presented)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            idle.isActive = phase == .active
            idle.recordActivity()
        }
        .task(id: [idleMinutes, scenePhase == .active ? 1 : 0]) {
            idle.recordActivity()
            guard idleMinutes > 0, scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                idle.check(timeout: .seconds(idleMinutes * 60))
            }
        }
    }
}

@MainActor @Observable final class IdleScreenState {
    private(set) var isVisible = false
    var isActive = true
    private var presentationBlocked = false
    private var mediaActive = false
    private var lastActivity = ContinuousClock.now
    func preview() { if isActive && !mediaActive { isVisible = true } }
    func recordActivity(at instant: ContinuousClock.Instant = .now) {
        lastActivity = instant
        if isVisible { isVisible = false }
    }
    func setPresentationBlocked(_ blocked: Bool) {
        presentationBlocked = blocked
        if blocked { recordActivity() }
    }
    func setMediaActive(_ active: Bool) {
        mediaActive = active
        recordActivity()
    }
    func check(timeout: Duration, at instant: ContinuousClock.Instant = .now) {
        guard isActive, !presentationBlocked, !mediaActive, timeout > .zero else { return }
        let visible = lastActivity.duration(to: instant) >= timeout
        if isVisible != visible { isVisible = visible }
    }
}

/// A passive window recognizer observes touches without competing with scrolling,
/// controls, or reader gestures. It is removed with this profile's view hierarchy.
private struct IdleActivityObserver: UIViewRepresentable {
    let activity: () -> Void
    let blocked: (Bool) -> Void
    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.activity = activity
        view.blocked = blocked
        return view
    }
    func updateUIView(_ view: ObserverView, context: Context) {
        view.activity = activity
        view.blocked = blocked
    }
    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.detach() }

    final class ObserverView: UIView {
        var activity: () -> Void = {}
        var blocked: (Bool) -> Void = { _ in }
        private weak var observedWindow: UIWindow?
        private var touchObserver: ActivityGesture?
        private var polling: Task<Void, Never>?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard let window else { return }
            observedWindow = window
            let gesture = ActivityGesture()
            gesture.activity = { [weak self] in self?.activity() }
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            window.addGestureRecognizer(gesture)
            touchObserver = gesture
            polling = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.blocked(
                        self.observedWindow?.rootViewController?.presentedViewController != nil
                            || UIAccessibility.isVoiceOverRunning
                            || UIAccessibility.isSwitchControlRunning)
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
            NotificationCenter.default.addObserver(
                self, selector: #selector(edited),
                name: UITextField.textDidChangeNotification, object: nil)
            NotificationCenter.default.addObserver(
                self, selector: #selector(edited),
                name: UITextView.textDidChangeNotification, object: nil)
        }
        @objc private func edited() { activity() }
        func detach() {
            if let touchObserver { observedWindow?.removeGestureRecognizer(touchObserver) }
            polling?.cancel()
            polling = nil
            touchObserver = nil
            observedWindow = nil
            NotificationCenter.default.removeObserver(self)
        }
    }
    final class ActivityGesture: UIGestureRecognizer {
        var activity: () -> Void = {}
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            activity()
            state = .began
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            activity()
            state = .changed
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            activity()
            state = .ended
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            state = .cancelled
        }
        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

struct GeneralMediaPresentedKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

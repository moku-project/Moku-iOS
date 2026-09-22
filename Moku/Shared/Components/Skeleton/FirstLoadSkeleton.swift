import SwiftUI

/// Presentation state is session-local; disposable response data lives in Library/Caches.
@MainActor @Observable
final class SkeletonVisits {
    static let shared = SkeletonVisits()
    private var completed: Set<String> = []
    private(set) var generation = 0
    func contains(_ key: String) -> Bool { completed.contains(key) }
    func complete(_ key: String) { completed.insert(key) }
    func clear() {
        completed.removeAll()
        generation += 1
    }
}

extension EnvironmentValues {
    @Entry var skeletonStorageScope = "startup"
}

private struct FirstLoadSkeleton: ViewModifier {
    let key: String
    let enabled: Bool
    let loading: Bool
    let style: ContentSkeleton.Style
    @Environment(\.skeletonStorageScope) private var profile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("preferences.animations") private var animations = true
    @State private var finishedCycle: String?
    private var visits: SkeletonVisits { .shared }
    private var identity: String { "\(profile):\(key):\(visits.generation)" }
    private var motion: Bool { !reduceMotion && animations }
    private var showing: Bool {
        enabled && !visits.contains(identity) && (loading || (motion && finishedCycle != identity))
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content.opacity(showing ? 0 : 1)
                .allowsHitTesting(!showing).accessibilityHidden(showing)
            if showing { ContentSkeleton(style: style).padding(style == .cover ? 0 : 16) }
        }
        .task(id: "\(identity):\(motion):\(scenePhase == .active)") {
            guard enabled, !visits.contains(identity) else { return }
            let current = identity
            if motion {
                guard scenePhase == .active else { return }
                do { try await Task.sleep(for: .seconds(SkeletonTiming.cycle)) } catch { return }
            }
            guard !Task.isCancelled, identity == current else { return }
            finishedCycle = current
        }
        .onChange(of: showing) { _, showing in
            if enabled && !showing { visits.complete(identity) }
        }
    }
}

enum SkeletonTiming {
    static let halfCycle = 1.1
    static let cycle = halfCycle * 2
}

extension View {
    func firstLoadSkeleton(
        _ key: String, loading: Bool, style: ContentSkeleton.Style, enabled: Bool = true
    ) -> some View {
        modifier(FirstLoadSkeleton(key: key, enabled: enabled, loading: loading, style: style))
    }
}

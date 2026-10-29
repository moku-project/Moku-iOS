import SwiftUI

/// Presentation state is session-local; disposable response data lives in Library/Caches.
@MainActor @Observable
final class SkeletonVisits {
    static let shared = SkeletonVisits()
    @ObservationIgnored private var completed: Set<String> = []
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
    private var visits: SkeletonVisits { .shared }
    private var identity: String { "\(profile):\(key):\(visits.generation)" }
    private var showing: Bool {
        enabled && loading && !visits.contains(identity)
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content.opacity(showing ? 0 : 1)
                .allowsHitTesting(!showing).accessibilityHidden(showing)
            if showing { ContentSkeleton(style: style).padding(style == .cover ? 0 : 16) }
        }
        // Loading controls visibility; decorative animation must never delay ready content.
        .onChange(of: loading, initial: true) { _, loading in
            if enabled && !loading { visits.complete(identity) }
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

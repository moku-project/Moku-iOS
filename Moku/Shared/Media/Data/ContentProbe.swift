import Foundation

/// Checks search results for chapters before they are trusted. Sources such as
/// MangaDex still list titles whose chapters were removed (licensed series);
/// those come back with no chapters and are hidden from typed searches.
/// A few checks run at once, and answers are kept for six hours.
actor ContentProbe {
    enum Verdict: Equatable, Sendable { case content, empty, unknown }

    static let shared = ContentProbe()
    private let limit: Int
    private let lifetime: TimeInterval
    private var known: [String: (hasContent: Bool, at: Date)] = [:]
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int = 4, lifetime: TimeInterval = 6 * 3600) {
        self.limit = limit
        self.lifetime = lifetime
    }

    static func key(_ entry: MediaEntry) -> String? {
        guard let source = entry.extensionID, let external = entry.externalID else { return nil }
        return source + "\u{1F}" + external
    }

    /// A failed or unanswerable check is `.unknown`, and the title stays visible.
    func verdict(
        for entry: MediaEntry, count: @Sendable (MediaEntry) async throws -> Int?
    ) async -> Verdict {
        guard let key = Self.key(entry) else { return .unknown }
        if let cached = known[key], Date.now.timeIntervalSince(cached.at) < lifetime {
            return cached.hasContent ? .content : .empty
        }
        await acquire()
        defer { release() }
        if let cached = known[key], Date.now.timeIntervalSince(cached.at) < lifetime {
            return cached.hasContent ? .content : .empty
        }
        guard !Task.isCancelled, let chapters = try? await count(entry) else { return .unknown }
        known[key] = (chapters > 0, .now)
        if known.count > 1000 { known = known.filter { Date.now.timeIntervalSince($0.value.at) < lifetime } }
        return chapters > 0 ? .content : .empty
    }

    private func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        // Hand the slot straight to the next waiter, so `active` stays accurate.
        if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() }
    }
}

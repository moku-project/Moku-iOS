import Foundation
import Testing

@testable import Moku

/// Search results with no chapters at their source are hidden from typed searches.
struct ForwardFetchTests {
    private static func entry(_ id: String) -> MediaEntry {
        MediaEntry(id: id, title: id.capitalized, media: .manga, sourceName: "One", coverURL: nil,
                   extensionID: "one", externalID: "/\(id)")
    }

    @Test func probeCachesAnswersAndKeepsUnknownTitles() async {
        let probe = ContentProbe()
        let calls = CallLog()
        let count: @Sendable (MediaEntry) async throws -> Int? = { entry in
            await calls.add(entry.id)
            switch entry.id {
            case "empty": return 0
            case "broken": throw URLError(.timedOut)
            case "fixture": return nil
            default: return 12
            }
        }
        #expect(await probe.verdict(for: Self.entry("full"), count: count) == .content)
        #expect(await probe.verdict(for: Self.entry("full"), count: count) == .content)
        #expect(await probe.verdict(for: Self.entry("empty"), count: count) == .empty)
        #expect(await probe.verdict(for: Self.entry("broken"), count: count) == .unknown)
        #expect(await probe.verdict(for: Self.entry("fixture"), count: count) == .unknown)
        // No source identity: nothing to check.
        let bare = MediaEntry(id: "bare", title: "Bare", media: .manga, sourceName: "One", coverURL: nil)
        #expect(await probe.verdict(for: bare, count: count) == .unknown)
        #expect(await calls.ids.filter { $0 == "full" }.count == 1)
    }

    @Test func probeRunsAFewChecksAtOnce() async {
        let probe = ContentProbe(limit: 2)
        let gauge = Gauge()
        let count: @Sendable (MediaEntry) async throws -> Int? = { _ in
            await gauge.enter()
            try? await Task.sleep(for: .milliseconds(30))
            await gauge.leave()
            return 1
        }
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<8 { group.addTask { _ = await probe.verdict(for: Self.entry("t\(index)"), count: count) } }
        }
        #expect(await gauge.peak == 2)
    }

    @MainActor @Test func typedSearchHidesTitlesWithoutChapters() async throws {
        let model = SearchViewModel(repository: ChapterlessResults(), debounce: .milliseconds(10), probe: ContentProbe())
        model.query = "rent a girlfriend"
        try await waitUntil { if case .results(let items) = model.state { items.count == 2 } else { false } }
        guard case .results(let items) = model.state else { Issue.record("No results"); return }
        #expect(items.map(\.id) == ["kept", "unknown"])
        #expect(model.hiddenEmpty == 1)
    }

    @MainActor @Test func hidingCanBeTurnedOff() async throws {
        let model = SearchViewModel(repository: ChapterlessResults(), debounce: .milliseconds(10), probe: ContentProbe())
        model.draft.hidesEmpty = false
        model.apply()
        model.query = "rent a girlfriend"
        try await waitUntil { if case .results(let items) = model.state { items.count == 3 } else { false } }
        try await Task.sleep(for: .milliseconds(100))
        guard case .results(let items) = model.state else { Issue.record("No results"); return }
        #expect(items.count == 3)
        #expect(model.hiddenEmpty == 0)
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }
}

private struct ChapterlessResults: SearchRepository {
    func sources() async throws -> [SearchSource] {
        [SearchSource(id: "one", name: "One", language: "en", media: .manga, isPinned: false)]
    }
    func search(_ request: SearchRequest) async throws -> [MediaEntry] {
        ["kept", "empty", "unknown"].map {
            MediaEntry(id: $0, title: $0, media: .manga, sourceName: "One", coverURL: nil,
                       extensionID: "one", externalID: "/\($0)")
        }
    }
    func chapterCount(_ entry: MediaEntry) async throws -> Int? {
        switch entry.id {
        case "kept": 40
        case "empty": 0
        default: throw URLError(.cannotConnectToHost)
        }
    }
}

private actor CallLog {
    private(set) var ids: [String] = []
    func add(_ id: String) { ids.append(id) }
}

private actor Gauge {
    private var now = 0
    private(set) var peak = 0
    func enter() { now += 1; peak = max(peak, now) }
    func leave() { now -= 1 }
}

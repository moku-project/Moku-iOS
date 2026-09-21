import Foundation
import Testing

@testable import Moku

struct SearchHistoryTests {
    @Test func persistsDeduplicatesAndSafelyStoresQuotedQueries() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "history.sqlite")
        let store = SearchHistoryStore(url: url)
        _ = try await store.record("  Moon  ")
        _ = try await store.record("reader's \"choice\"; DROP TABLE search_history;")
        _ = try await store.record("MOON")
        _ = try await store.record(" \n ")
        let reopened = SearchHistoryStore(url: url)
        let rows = try await reopened.recent()
        #expect(rows.map(\.query) == ["MOON", "reader's \"choice\"; DROP TABLE search_history;"])
        let remaining = try await reopened.remove(id: rows[0].id)
        #expect(remaining.count == 1)
        #expect(try await reopened.remove().isEmpty)
        #expect(try await store.recent().isEmpty)
    }

    @Test func capsHistoryAndKeepsProfilesSeparate() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = SearchHistoryStore(url: root.appending(path: "first/history.sqlite"))
        let second = SearchHistoryStore(url: root.appending(path: "second/history.sqlite"))
        for index in 0..<35 { _ = try await first.record("Title \(index)") }
        let rows = try await first.recent()
        #expect(rows.count == 30)
        #expect(rows.first?.query == "Title 34")
        #expect(!rows.contains { $0.query == "Title 0" })
        #expect(try await second.recent().isEmpty)
        _ = try await second.record("Other profile")
        _ = try await first.remove()
        #expect(try await second.recent().map(\.query) == ["Other profile"])
    }
}

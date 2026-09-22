import Foundation
import Testing

@testable import Moku

@MainActor struct LibraryPersistenceTests {
    @Test func savedTitlesPersistInTheirStorageDirectory() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = LibraryStore(directory: root.appending(path: "first"))
        let second = LibraryStore(directory: root.appending(path: "second"))
        let entry = MediaEntry(
            id: "title", title: "A title", media: .manga, sourceName: "Source", coverURL: nil)
        #expect(await first.setSaved(true, entry: entry))
        await second.load()
        #expect(first.contains(entry) && !second.contains(entry))
        let restored = LibraryStore(directory: root.appending(path: "first"))
        await restored.load()
        #expect(restored.contains(entry))
        #expect(await first.setSaved(false, entry: entry))
        #expect(!first.contains(entry))
    }
}

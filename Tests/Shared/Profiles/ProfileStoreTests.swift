import Foundation
import Testing

@testable import Moku

@MainActor struct ProfileStoreTests {
    @Test func profilesPersistAndPreferencesStaySeparate() async throws {
        let id = UUID().uuidString
        let root = URL.temporaryDirectory.appending(path: id)
        let prefix = "test.moku.\(id)"
        let store = ProfileStore(root: root, defaultsPrefix: prefix)
        defer {
            try? FileManager.default.removeItem(at: root)
            for profile in store.profiles {
                UserDefaults.standard.removePersistentDomain(
                    forName: "\(prefix).\(profile.id.uuidString)")
            }
        }
        await store.load()
        #expect(store.loaded && store.profiles.count == 1)
        let first = store.activeID
        #expect(await store.add(name: "  Second  "))
        let second = try #require(store.profiles.last)
        #expect(second.name == "Second")
        #expect(first != second.id)
        store.preferences(for: first).set("sepia", forKey: "preferences.theme")
        #expect(store.preferences(for: second.id).string(forKey: "preferences.theme") == nil)
        #expect(await store.select(second.id))
        #expect(await store.rename(second, name: "Updated"))
        let restored = ProfileStore(root: root, defaultsPrefix: prefix)
        await restored.load()
        #expect(restored.active?.name == "Updated")
        #expect(restored.homeURL(for: first) == root.appending(path: "home.json"))
        #expect(restored.homeURL(for: first) != restored.homeURL(for: second.id))
    }

    @Test func corruptManifestIsNotOverwritten() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "profiles.json")
        let original = Data("invalid".utf8)
        try original.write(to: url)
        let store = ProfileStore(root: root)
        await store.load()
        #expect(!store.loaded && store.error != nil)
        #expect(!(await store.add(name: "No overwrite")))
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func savedTitlesRemainInTheirOwnProfile() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = ProfileLibrary(directory: root.appending(path: "first"))
        let second = ProfileLibrary(directory: root.appending(path: "second"))
        let entry = MediaEntry(
            id: "title", title: "A title", media: .manga, sourceName: "Source", coverURL: nil)
        #expect(await first.setSaved(true, entry: entry))
        await second.load()
        #expect(first.contains(entry) && !second.contains(entry))
        let restored = ProfileLibrary(directory: root.appending(path: "first"))
        await restored.load()
        #expect(restored.contains(entry))
        #expect(await first.setSaved(false, entry: entry))
        #expect(!first.contains(entry))
    }
}

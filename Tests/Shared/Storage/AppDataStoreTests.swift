import Foundation
import Testing

@testable import Moku

@MainActor struct AppDataStoreTests {
    @Test func freshInstallUsesOneStableStore() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppDataStore(root: root)
        await store.load()
        #expect(store.loaded)
        #expect(store.directory == root.appending(path: "Data"))
        let restored = AppDataStore(root: root)
        await restored.load()
        #expect(restored.directory == store.directory)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "profiles.json").path))
    }

    @Test func keepsLastActiveDataAndPreferences() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let id = UUID()
        let prefix = "test.moku.\(UUID().uuidString)"
        let suite = "\(prefix).profile.\(id.uuidString)"
        defer {
            try? FileManager.default.removeItem(at: root)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = try JSONSerialization.data(withJSONObject: [
            "profiles": [["id": id.uuidString, "name": "Reader"]], "activeID": id.uuidString,
        ])
        let manifestURL = root.appending(path: "profiles.json")
        try manifest.write(to: manifestURL)
        let directory = root.appending(path: "Profiles/\(id.uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let library = Data("[]".utf8)
        try library.write(to: directory.appending(path: "library.json"))
        UserDefaults(suiteName: suite)!.set("sepia", forKey: "preferences.theme")
        let store = AppDataStore(root: root, defaultsPrefix: prefix)
        await store.load()
        #expect(store.loaded)
        #expect(store.directory == directory)
        #expect(store.homeURL == directory.appending(path: "home.json"))
        #expect(store.preferences.string(forKey: "preferences.theme") == "sepia")
        #expect(try Data(contentsOf: manifestURL) == manifest)
        #expect(try Data(contentsOf: directory.appending(path: "library.json")) == library)
        try Data("invalid".utf8).write(to: manifestURL)
        let restored = AppDataStore(root: root, defaultsPrefix: prefix)
        await restored.load()
        #expect(restored.loaded && restored.directory == directory)
    }

    @Test func keepsOriginalHomeHistoryLocation() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = "00000000-0000-0000-0000-000000000001"
        try JSONSerialization.data(withJSONObject: ["profiles": [["id": id]], "activeID": id])
            .write(to: root.appending(path: "profiles.json"))
        let store = AppDataStore(root: root)
        await store.load()
        #expect(store.loaded)
        #expect(store.homeURL == root.appending(path: "home.json"))
    }

    @Test func corruptLegacyManifestDoesNotResetData() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = Data("invalid".utf8)
        let url = root.appending(path: "profiles.json")
        try original.write(to: url)
        let store = AppDataStore(root: root)
        await store.load()
        #expect(!store.loaded && store.error != nil)
        #expect(try Data(contentsOf: url) == original)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "app-data.json").path))
    }
}

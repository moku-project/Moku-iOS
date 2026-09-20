import Foundation
import Testing
@testable import Moku

@MainActor struct SettingsParityTests {
    @Test func shortcutsRejectMalformedChordsAndCanonicalizeModifierOrder() {
        #expect(ReaderShortcut.valid("ctrl+shift+ArrowLeft"))
        #expect(ReaderShortcut.valid(""))
        #expect(!ReaderShortcut.valid("ctrl+ctrl+x"))
        #expect(!ReaderShortcut.valid("ctrl+"))
        #expect(!ReaderShortcut.valid("hyper+x"))
        #expect(ReaderShortcut.normalized("SHIFT+ctrl+x") == ReaderShortcut.normalized("ctrl+shift+x"))
    }

    @Test func libraryLinksMatchingTitlesWithoutMixingMedia() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        let first = MediaEntry(id: "1", title: "Café: Story", media: .manga, sourceName: "A", coverURL: nil)
        let second = MediaEntry(id: "2", title: "Cafe Story", media: .manga, sourceName: "B", coverURL: nil)
        let anime = MediaEntry(id: "3", title: "Cafe Story", media: .anime, sourceName: "C", coverURL: nil)
        for entry in [first, second, anime] { #expect(await store.setSaved(true, entry: entry)) }
        await store.autoLink(first)
        #expect(store.linkedEntries(for: first.id) == [second])
        #expect(store.linkedEntries(for: second.id) == [first])
        let restored = LibraryStore(directory: directory)
        await restored.load()
        await restored.loadOrganization()
        #expect(restored.linkedEntries(for: first.id) == [second])
    }

    @Test func oldFoldersRemainReadableAndFlagsPersist() async throws {
        let id = UUID()
        let old = Data("{\"id\":\"\(id)\",\"name\":\"Favorites\",\"entryIDs\":[\"1\"]}".utf8)
        var folder = try JSONDecoder().decode(LibraryFolder.self, from: old)
        #expect(folder.includeInUpdate == nil)
        folder.hidden = true
        folder.includeInUpdate = false
        folder.includeInDownload = false
        #expect(try JSONDecoder().decode(LibraryFolder.self, from: JSONEncoder().encode(folder)) == folder)
    }

    @Test func settingsExportExcludesLockCredentialsAndRejectsForeignKeys() throws {
        let suite = "settings-parity-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "player.autoSubtitles")
        defaults.set(true, forKey: "appLock.biometrics")
        defaults.set("private", forKey: "backend.token")
        let archive = try SettingsArchive(defaults: defaults)
        let values = try archive.validatedValues()
        #expect(values["player.autoSubtitles"] as? Bool == true)
        #expect(values["appLock.biometrics"] == nil)
        #expect(values["backend.token"] == nil)
        let raw = try JSONSerialization.data(withJSONObject: ["version": 1, "values": ["backend.token": Data().base64EncodedString()]])
        let foreign = try JSONDecoder().decode(SettingsArchive.self, from: raw)
        #expect(throws: (any Error).self) { try foreign.validatedValues() }
    }

    @Test func appLockPersistsPinAndLimitsWrongAttempts() throws {
        let suite = "lock-parity-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let lock = AppLockStore(defaults: defaults, scope: suite)
        #expect(!lock.enabled)
        try lock.configure(pin: "123456", currentPIN: "")
        defer {
            defaults.removeObject(forKey: "appLock.retryAt")
            try? lock.disable(pin: "123456")
        }
        let restored = AppLockStore(defaults: defaults, scope: suite)
        #expect(restored.enabled && restored.locked)
        for _ in 0..<5 { restored.unlock(pin: "654321") }
        restored.unlock(pin: "123456")
        #expect(restored.locked)
        defaults.set(Date().timeIntervalSince1970 - 1, forKey: "appLock.retryAt")
        restored.unlock(pin: "123456")
        #expect(!restored.locked)
        #expect(defaults.integer(forKey: "appLock.attempts") == 0)
    }
}

import Foundation
import Observation

/// One app data store. Old profile files are read only to preserve the last active library.
@MainActor @Observable
final class AppDataStore {
    static let shared = AppDataStore()
    static let root = URL.applicationSupportDirectory.appending(path: "Moku")
    private static let legacyPrimaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private(set) var loaded = false
    private(set) var error: String?
    private let root: URL
    private let defaultsPrefix: String
    private var location = Location()

    init(root: URL = AppDataStore.root, defaultsPrefix: String = "com.moku") {
        self.root = root
        self.defaultsPrefix = defaultsPrefix
    }

    static func makeDefault() -> AppDataStore {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-storage"),
                let value = UserDefaults.standard.string(forKey: "mokuStorageTestID"),
                let id = UUID(uuidString: value)
            {
                return AppDataStore(
                    root: URL.temporaryDirectory.appending(
                        path: "MokuStorageUITest/\(id.uuidString)"),
                    defaultsPrefix: "com.moku.uitest.\(id.uuidString)")
            }
        #endif
        return shared
    }

    var directory: URL {
        if let id = location.legacyProfileID {
            return root.appending(path: "Profiles/\(id.uuidString)")
        }
        return root.appending(path: "Data")
    }

    var homeURL: URL {
        location.legacyProfileID == Self.legacyPrimaryID
            ? root.appending(path: "home.json") : directory.appending(path: "home.json")
    }

    var preferences: UserDefaults {
        let suite =
            location.legacyProfileID.map { "\(defaultsPrefix).profile.\($0.uuidString)" }
            ?? "\(defaultsPrefix).preferences"
        return UserDefaults(suiteName: suite)!
    }

    func load() async {
        guard !loaded else { return }
        do {
            let document = StoredDocument<Location>(url: root.appending(path: "app-data.json"))
            if let saved = try await document.read() {
                location = saved
            } else {
                let legacy = StoredDocument<LegacyManifest>(
                    url: root.appending(path: "profiles.json"))
                if let saved = try await legacy.read() {
                    guard !saved.profiles.isEmpty,
                        Set(saved.profiles.map(\.id)).count == saved.profiles.count,
                        saved.profiles.contains(where: { $0.id == saved.activeID })
                    else { throw CocoaError(.fileReadCorruptFile) }
                    location = Location(legacyProfileID: saved.activeID)
                } else if root == Self.root {
                    if FileManager.default.fileExists(
                        atPath: root.appending(path: "home.json").path)
                    {
                        location = Location(legacyProfileID: Self.legacyPrimaryID)
                    }
                    // Preserve settings from versions predating the profile picker.
                    for key in ["contentMode", "library.listLayout"]
                    where preferences.object(forKey: key) == nil {
                        if let value = UserDefaults.standard.object(forKey: key) {
                            preferences.set(value, forKey: key)
                        }
                    }
                }
                try await document.write(location)
            }
            loaded = true
            error = nil
        } catch {
            self.error = "Couldn’t load your saved data. Your files have not been changed."
        }
    }

    private struct Location: Codable, Sendable {
        var legacyProfileID: UUID?
    }
    private struct LegacyManifest: Codable, Sendable {
        struct Entry: Codable, Sendable { let id: UUID }
        let profiles: [Entry]
        let activeID: UUID
    }
}

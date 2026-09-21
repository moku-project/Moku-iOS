import Foundation
import Observation

@MainActor @Observable
final class ProfileStore {
    static let shared = ProfileStore()
    static let root = URL.applicationSupportDirectory.appending(path: "Moku")
    private(set) var profiles: [LocalProfile] = []
    private(set) var activeID = LocalProfile.primaryID
    private(set) var loaded = false
    private(set) var busy = false
    var error: String?
    let root: URL
    private let document: ProfileDocument<ProfileManifest>
    private let defaultsPrefix: String

    init(root: URL = ProfileStore.root, defaultsPrefix: String = "com.moku.profile") {
        self.root = root
        self.defaultsPrefix = defaultsPrefix
        document = ProfileDocument(url: root.appending(path: "profiles.json"))
    }

    static func makeDefault() -> ProfileStore {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-profiles"),
                let value = UserDefaults.standard.string(forKey: "mokuProfileTestID"),
                let id = UUID(uuidString: value)
            {
                return ProfileStore(
                    root: URL.temporaryDirectory.appending(
                        path: "MokuProfilesUITest/\(id.uuidString)"),
                    defaultsPrefix: "com.moku.uitest.\(id.uuidString)")
            }
        #endif
        return shared
    }

    var active: LocalProfile? { profiles.first { $0.id == activeID } }
    func directory(for id: UUID) -> URL { root.appending(path: "Profiles/\(id.uuidString)") }
    func homeURL(for id: UUID) -> URL {
        // Preserve the existing user's history in place during the first upgrade.
        id == LocalProfile.primaryID
            ? root.appending(path: "home.json") : directory(for: id).appending(path: "home.json")
    }
    func preferences(for id: UUID) -> UserDefaults {
        UserDefaults(suiteName: "\(defaultsPrefix).\(id.uuidString)")!
    }

    func load() async {
        guard !loaded, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if let saved = try await document.read() {
                guard !saved.profiles.isEmpty,
                    Set(saved.profiles.map(\.id)).count == saved.profiles.count,
                    saved.profiles.contains(where: { $0.id == saved.activeID })
                else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                profiles = saved.profiles
                activeID = saved.activeID
            } else {
                let migrateLegacy = root == Self.root && defaultsPrefix == "com.moku.profile"
                let name =
                    migrateLegacy
                    ? (UserDefaults.standard.string(forKey: "profile.displayName") ?? "") : ""
                let profile = LocalProfile(
                    id: LocalProfile.primaryID,
                    name: name.isEmpty ? "Default" : String(name.prefix(40)))
                let prefs = preferences(for: profile.id)
                for key in ["contentMode", "library.listLayout"]
                where migrateLegacy && prefs.object(forKey: key) == nil {
                    if let value = UserDefaults.standard.object(forKey: key) {
                        prefs.set(value, forKey: key)
                    }
                }
                try await document.write(ProfileManifest(profiles: [profile], activeID: profile.id))
                profiles = [profile]
                activeID = profile.id
            }
            loaded = true
            error = nil
        } catch { self.error = "Couldn’t load profiles. Your saved data has not been changed." }
    }

    @discardableResult func add(name: String) async -> Bool {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty else { return false }
        let profile = LocalProfile(id: UUID(), name: name)
        return await commit(profiles: profiles + [profile], activeID: activeID)
    }

    @discardableResult func rename(_ profile: LocalProfile, name: String) async -> Bool {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty, let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return false
        }
        var updated = profiles
        updated[index].name = name
        return await commit(profiles: updated, activeID: activeID)
    }

    @discardableResult func select(_ id: UUID) async -> Bool {
        guard profiles.contains(where: { $0.id == id }) else { return false }
        return await commit(profiles: profiles, activeID: id)
    }

    private func commit(profiles: [LocalProfile], activeID: UUID) async -> Bool {
        guard loaded, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            try await document.write(ProfileManifest(profiles: profiles, activeID: activeID))
            self.profiles = profiles
            self.activeID = activeID
            error = nil
            return true
        } catch {
            self.error = "Couldn’t save profiles. Try again."
            return false
        }
    }
}

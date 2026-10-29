import Foundation
import Observation

struct ServerStorageInfo: Decodable, Sendable {
    let usedBytes: Double
    let totalBytes: Double
    let freeBytes: Double
    let dataDir: String
    let mediaDir: String
    let databasePath: String
    let categories: [Category]
    struct Category: Decodable, Identifiable, Sendable {
        let key: String
        let label: String
        let path: String
        let bytes: Double
        let fileCount: Int
        let clearable: Bool
        var id: String { key }
    }
}
struct ServerBackup: Decodable, Identifiable, Sendable {
    let name: String
    let path: String
    let bytes: Double
    let createdAt: String
    let kind: String
    var id: String { name }
}
struct IgnoredGraphQLResult: Decodable, Sendable { init(from decoder: any Decoder) throws {} }
@MainActor @Observable final class StoragePreferences {
    var info: ServerStorageInfo?
    var backups: [ServerBackup] = []
    var busy = false
    var notice: String?
    func load() async {
        busy = true
        defer { busy = false }
        do {
            struct Result: Decodable, Sendable { let storageInfo: ServerStorageInfo; let databaseBackups: [ServerBackup] }
            let result: Result = try await BackendAPI.shared.graphql("{ storageInfo { usedBytes totalBytes freeBytes dataDir mediaDir databasePath categories { key label path bytes fileCount clearable } } databaseBackups { name path bytes createdAt kind } }", requiresSourceRuntime: false)
            info = result.storageInfo
            backups = result.databaseBackups
            notice = nil
        } catch { notice = "Couldn’t load storage information. Try again." }
    }
    @discardableResult func run(_ mutation: String) async -> Bool {
        guard !busy else { return false }
        busy = true
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql("mutation { \(mutation) }", requiresSourceRuntime: false)
            await load()
            busy = false
            return true
        } catch { notice = "Couldn’t complete this storage action. Try again."; busy = false; return false }
    }
    func backupData(_ backup: ServerBackup) async throws -> Data {
        guard let info else { throw CocoaError(.fileReadUnknown) }
        let root = URL(fileURLWithPath: info.dataDir).appending(path: "backups").resolvingSymlinksInPath()
        let url = URL(fileURLWithPath: backup.path).resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/"), url.lastPathComponent == backup.name else { throw CocoaError(.fileReadNoPermission) }
        return try await Task.detached { try Data(contentsOf: url) }.value
    }
}

struct SettingsArchive: Codable, Sendable {
    let version: Int
    let values: [String: Data]
    static let prefixes = ["preferences.", "library.", "reader.", "player.", "keybinds.", "downloads."]
    static func permitted(_ key: String) -> Bool { prefixes.contains { key.hasPrefix($0) } || key == "contentMode" }
    init(defaults: UserDefaults) throws {
        version = 1
        var result: [String: Data] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where Self.permitted(key) {
            result[key] = try PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0)
        }
        values = result
    }
    func validatedValues() throws -> [String: Any] {
        guard version == 1, values.count <= 500 else { throw CocoaError(.coderReadCorrupt) }
        var result: [String: Any] = [:]
        for (key, data) in values {
            guard Self.permitted(key), data.count <= 8 * 1024 * 1024,
                let record = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                let value = record["value"] else { throw CocoaError(.coderReadCorrupt) }
            if key == "reader.preferences.v1" {
                guard let raw = value as? Data else { throw CocoaError(.coderReadCorrupt) }
                let document = try JSONDecoder().decode(ReaderPreferenceDocument.self, from: raw)
                let settings = [document.global] + Array(document.overrides.values) + document.presets.map(\.settings)
                guard settings.allSatisfy({
                    ["single", "double", "auto", "longstrip"].contains($0.pageStyle)
                    && ["none", "fade", "slide", "flip"].contains($0.transition)
                    && ["width", "height", "screen", "original"].contains($0.fitMode)
                    && ["ltr", "rtl"].contains($0.readingDirection)
                    && $0.readerZoom.isFinite && (0.1...1).contains($0.readerZoom)
                    && ["top", "bottom", "left", "right"].contains($0.barPosition)
                }), (0...10).contains(document.behaviour.preloadPages),
                    document.behaviour.autoScrollSpeed.isFinite,
                    (1...30).contains(document.behaviour.autoScrollSpeed),
                    document.positions.values.allSatisfy({ $0.page >= 1 }),
                    document.bookmarks.values.allSatisfy({ $0.page >= 1 })
                else { throw CocoaError(.coderReadCorrupt) }
            }
            if key == "preferences.customThemes" {
                guard let raw = value as? Data else { throw CocoaError(.coderReadCorrupt) }
                let themes = raw.isEmpty ? [] : try JSONDecoder().decode([NativeTheme].self, from: raw)
                guard themes.count <= 100, Set(themes.map(\.id)).count == themes.count,
                    themes.allSatisfy({ theme in
                        !theme.name.isEmpty && !theme.id.isEmpty && !NativeTheme.builtins.contains(where: { $0.id == theme.id })
                        && [theme.background, theme.surface, theme.accent, theme.text, theme.secondary, theme.muted, theme.border].allSatisfy { value in
                            value.count == 7 && value.first == "#" && UInt32(value.dropFirst(), radix: 16) != nil
                        }
                    }) else { throw CocoaError(.coderReadCorrupt) }
            }
            if key == "keybinds.reader" {
                guard let raw = value as? Data else { throw CocoaError(.coderReadCorrupt) }
                let bindings = raw.isEmpty ? [:] : try JSONDecoder().decode([String: String].self, from: raw)
                guard bindings.values.allSatisfy(ReaderShortcut.valid) else { throw CocoaError(.coderReadCorrupt) }
                let assigned = bindings.values.filter { !$0.isEmpty }.map(ReaderShortcut.normalized)
                guard Set(assigned).count == assigned.count else { throw CocoaError(.coderReadCorrupt) }
            }
            result[key] = value
        }
        return result
    }
}

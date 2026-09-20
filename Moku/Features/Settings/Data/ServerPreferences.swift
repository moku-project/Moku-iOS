import Foundation
import Observation

struct ServerPreference: Codable, Identifiable, Sendable {
    let key: String
    var value: String
    let type: String
    let scope: String
    let source: String
    let editable: Bool
    let description: String
    var id: String { key }
    var label: String {
        switch key {
        case "cloudflare_solver_mode": "Cloudflare solver"
        case "cloudflare_solver_url": "Solver URL"
        case "content_filter_level": "Content level"
        case "manga_download_format": "Download format"
        default: key.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        }
    }
    var choices: [(String, String)] {
        switch key {
        case "cloudflare_solver_mode": [("disabled", "Disabled"), ("external", "External")]
        case "content_filter_level": [("strict", "Strict"), ("moderate", "Moderate"), ("unrestricted", "Unrestricted")]
        case "manga_download_format": [("loose", "Images"), ("cbz", "CBZ")]
        default: []
        }
    }
}

@MainActor @Observable final class ServerPreferences {
    private(set) var values: [ServerPreference] = []
    private(set) var loading = false
    private(set) var saving = false
    var notice: String?
    private static let fields = "key value type scope source editable description"
    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            struct Result: Decodable, Sendable { let serverSettings: [ServerPreference] }
            let result: Result = try await BackendAPI.shared.graphql("{ serverSettings { \(Self.fields) } }", requiresSourceRuntime: false)
            values = result.serverSettings
            notice = nil
        } catch { notice = "Couldn’t load server settings. Try again." }
    }
    func save(_ setting: ServerPreference, value: String) async {
        guard !saving, setting.editable, setting.value != value else { return }
        saving = true
        defer { saving = false }
        do {
            struct Update: Decodable, Sendable { let setting: ServerPreference; let restartRequired: Bool }
            struct Result: Decodable, Sendable { let updateServerSetting: Update }
            let result: Result = try await BackendAPI.shared.graphql("mutation { updateServerSetting(key: \(BackendAPI.literal(setting.key)), value: \(BackendAPI.literal(value))) { setting { \(Self.fields) } restartRequired } }", requiresSourceRuntime: false)
            if let index = values.firstIndex(where: { $0.key == setting.key }) { values[index] = result.updateServerSetting.setting }
            notice = result.updateServerSetting.restartRequired ? "Saved. Restart Moku to apply this setting." : nil
        } catch { notice = "Couldn’t save \(setting.label). Check the value and try again." }
    }
}

struct ContentRule: Codable, Identifiable, Sendable {
    let id: String
    let category: String
    let field: String
    let keyword: String
    let minWeight: Int
    let blockLevel: String
    let isDefault: Bool
}

@MainActor @Observable final class ContentRules {
    var rules: [ContentRule] = []
    var busy = false
    var notice: String?
    static let fields = "id category field keyword minWeight blockLevel isDefault"
    func load() async {
        busy = true
        defer { busy = false }
        do {
            struct Result: Decodable, Sendable { let contentFilterRules: [ContentRule] }
            let result: Result = try await BackendAPI.shared.graphql("{ contentFilterRules { \(Self.fields) } }", requiresSourceRuntime: false)
            rules = result.contentFilterRules
            notice = nil
        } catch { notice = "Couldn’t load content rules." }
    }
    func change(_ mutation: String) async {
        guard !busy else { return }
        busy = true
        do {
            let _: [String: Bool] = try await BackendAPI.shared.graphql("mutation { \(mutation) }", requiresSourceRuntime: false)
            await load()
        } catch { notice = "Couldn’t update content rules." }
        busy = false
    }
    func add(category: String, field: String, keyword: String, weight: Int, level: String) async {
        guard !busy else { return }
        busy = true
        do {
            struct Result: Decodable, Sendable { let addContentFilterRule: ContentRule }
            let result: Result = try await BackendAPI.shared.graphql("mutation { addContentFilterRule(category: \(BackendAPI.literal(category)), field: \(field), keyword: \(BackendAPI.literal(keyword)), minWeight: \(weight), blockLevel: \(level)) { \(Self.fields) } }", requiresSourceRuntime: false)
            rules.append(result.addContentFilterRule)
            notice = nil
        } catch { notice = "Couldn’t add the content rule." }
        busy = false
    }
}

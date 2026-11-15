import SwiftUI

struct DownloadPolicy: Codable, Equatable, Sendable {
    var pauseUpdates = false
    var refreshInterval = "manual"
    var autoDownload = false
    var downloadAhead = 0
    var deleteOnRead = false
    var deleteDelayHours = 0
    var maxKeepChapters = 0
}
struct AutomationControls: Codable, Sendable {
    var enabled = true
    var enforceGlobal = false
    var updateOnOpen = true
}

/// Automation rules live in Tsunagu (GraphQL `automationSettings` /
/// `mediaAutomation`), shared with desktop and Android. Media ID "0" means the
/// global defaults.
@MainActor @Observable final class AutomationPreferences {
    var policy = DownloadPolicy()
    var controls = AutomationControls()
    var loaded = false
    var busy = false
    var notice: String?

    private struct Global: Decodable, Sendable {
        let enabled, enforceGlobal, updateOnOpen, autoDownload, deleteOnRead: Bool
        let downloadAhead, deleteDelayHours, maxKeepChapters: Int
        let refreshInterval: String
    }
    private struct GlobalResult: Decodable, Sendable { let automationSettings: Global }
    private struct Rules: Decodable, Sendable {
        let autoDownload, deleteOnRead, pauseUpdates: Bool
        let downloadAhead, deleteDelayHours, maxKeepChapters: Int
        let refreshInterval: String
    }
    private struct Series: Decodable, Sendable { let effective: Rules }
    private struct SeriesResult: Decodable, Sendable { let mediaAutomation: Series }

    private static let globalFields =
        "enabled enforceGlobal updateOnOpen autoDownload downloadAhead deleteOnRead deleteDelayHours maxKeepChapters refreshInterval"

    /// Series IDs are numeric; anything else is treated as the global defaults.
    private static func series(_ mediaID: String) -> Int64? {
        guard let id = Int64(mediaID), id > 0 else { return nil }
        return id
    }

    func load(mediaID: String = "0") async {
        busy = true
        defer { busy = false }
        do {
            let global: GlobalResult = try await BackendAPI.shared.graphql(
                "{ automationSettings { \(Self.globalFields) } }", requiresSourceRuntime: false)
            let g = global.automationSettings
            controls = AutomationControls(enabled: g.enabled, enforceGlobal: g.enforceGlobal, updateOnOpen: g.updateOnOpen)
            if let id = Self.series(mediaID) {
                let result: SeriesResult = try await BackendAPI.shared.graphql(
                    "{ mediaAutomation(mediaId: \"\(id)\") { effective { autoDownload downloadAhead deleteOnRead deleteDelayHours maxKeepChapters pauseUpdates refreshInterval } } }",
                    requiresSourceRuntime: false)
                let r = result.mediaAutomation.effective
                policy = DownloadPolicy(
                    pauseUpdates: r.pauseUpdates, refreshInterval: r.refreshInterval.lowercased(),
                    autoDownload: r.autoDownload, downloadAhead: r.downloadAhead, deleteOnRead: r.deleteOnRead,
                    deleteDelayHours: r.deleteDelayHours, maxKeepChapters: r.maxKeepChapters)
            } else {
                policy = DownloadPolicy(
                    pauseUpdates: false, refreshInterval: g.refreshInterval.lowercased(),
                    autoDownload: g.autoDownload, downloadAhead: g.downloadAhead, deleteOnRead: g.deleteOnRead,
                    deleteDelayHours: g.deleteDelayHours, maxKeepChapters: g.maxKeepChapters)
            }
            loaded = true
            notice = nil
        } catch { notice = "Couldn’t load automation settings. Try again." }
    }

    func savePolicy(_ value: DownloadPolicy, mediaID: String = "0") async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let interval = ["daily", "weekly", "manual"].contains(value.refreshInterval) ? value.refreshInterval.uppercased() : "MANUAL"
        let rules =
            "autoDownload: \(value.autoDownload), downloadAhead: \(value.downloadAhead), deleteOnRead: \(value.deleteOnRead), "
            + "deleteDelayHours: \(value.deleteDelayHours), maxKeepChapters: \(value.maxKeepChapters), refreshInterval: \(interval)"
        let mutation =
            if let id = Self.series(mediaID) {
                "mutation { setMediaAutomation(mediaId: \"\(id)\", input: { \(rules), pauseUpdates: \(value.pauseUpdates) }) { mediaId } }"
            } else {
                "mutation { updateAutomationSettings(input: { \(rules) }) { configured } }"
            }
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(mutation, requiresSourceRuntime: false)
            policy = value
            notice = nil
        } catch { notice = "Couldn’t save automation rules." }
    }

    func saveControls(_ value: AutomationControls) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                "mutation { updateAutomationSettings(input: { enabled: \(value.enabled), enforceGlobal: \(value.enforceGlobal), updateOnOpen: \(value.updateOnOpen) }) { configured } }",
                requiresSourceRuntime: false)
            controls = value
            notice = nil
        } catch { notice = "Couldn’t save automation controls." }
    }

    func resetSeries(_ mediaID: String) async {
        guard !busy, let id = Self.series(mediaID) else { return }
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                "mutation { resetMediaAutomation(mediaId: \"\(id)\") }", requiresSourceRuntime: false)
            await load(mediaID: mediaID)
        } catch { notice = "Couldn’t reset series rules." }
    }

    /// Clears every series' overrides.
    func resetOverrides() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                "mutation { resetMediaAutomation }", requiresSourceRuntime: false)
            notice = "Custom rules reset."
        } catch { notice = "Couldn’t reset custom rules." }
    }
}
struct AutomationSettingsContent: View {
    @State private var model = AutomationPreferences()
    @State private var reset = false
    @Environment(LibraryStore.self) private var library
    @State private var mediaID: String
    init(initialMediaID: String = "0") { _mediaID = State(initialValue: initialMediaID) }
    func policy<Value>(_ key: WritableKeyPath<DownloadPolicy, Value>) -> Binding<Value> {
        Binding(get: { model.policy[keyPath: key] }, set: { value in
            var next = model.policy; next[keyPath: key] = value
            Task { await model.savePolicy(next, mediaID: mediaID) }
        })
    }
    func controls(_ key: WritableKeyPath<AutomationControls, Bool>) -> Binding<Bool> {
        Binding(get: { model.controls[keyPath: key] }, set: { value in
            var next = model.controls; next[keyPath: key] = value
            Task { await model.saveControls(next) }
        })
    }
    @AppStorage("automation.backgroundUpdates") private var backgroundUpdates = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GeneralSection("Library updates") {
                GeneralRow("Update library on app open", detail: "Check every saved series for new chapters when Moku starts. Results appear in Recent → Updates.") {
                    Toggle("Update library on app open", isOn: controls(\.updateOnOpen)).toggleStyle(GeneralToggleStyle())
                }
                GeneralStyle.divider
                GeneralRow("Update in the background", detail: "iOS runs this while your iPhone is idle on a network, and Moku notifies you about new chapters.") {
                    Toggle("Update in the background", isOn: Binding(get: { backgroundUpdates }, set: { value in
                        backgroundUpdates = value
                        if value { Task { _ = await BackgroundWork.requestNotificationPermission() } }
                    })).toggleStyle(GeneralToggleStyle())
                }
            }
            GeneralSection("Behaviour") {
                row("Enable automation", detail: "Run rules while Moku is active.", value: controls(\.enabled))
                GeneralStyle.divider
                row("Enforce global defaults", detail: "Ignore per-series overrides.", value: controls(\.enforceGlobal))
            }
            GeneralSection("Rules") {
                GeneralRow("Apply to", detail: "Select global defaults or a saved series.") {
                    ChoicePicker(title: "", selection: $mediaID, options: [("0", "Global defaults")] + library.entries.filter { Int64($0.id) != nil }.map { ($0.id, $0.title) }).font(.subheadline)
                }
                GeneralStyle.divider
                row("Auto-download new chapters", detail: "Queue new chapters when a series refreshes.", value: policy(\.autoDownload))
                GeneralStyle.divider
                number("Download ahead", detail: "Queue upcoming chapters while reading.", value: policy(\.downloadAhead), options: [0, 1, 2, 3, 5, 10, 20, 50, 100])
                GeneralStyle.divider
                number("Max chapters to keep", detail: "0 keeps all downloaded chapters.", value: policy(\.maxKeepChapters), options: [0, 1, 5, 10, 20, 50, 100])
                GeneralStyle.divider
                row("Delete after reading", detail: "Remove completed chapter downloads.", value: policy(\.deleteOnRead))
                GeneralStyle.divider
                number("Delete delay", detail: "Hours after a chapter is marked read.", value: policy(\.deleteDelayHours), options: [0, 1, 6, 12, 24, 48, 72, 168])
                GeneralStyle.divider
                GeneralRow("Refresh interval", detail: "Check saved series for new chapters.") {
                    ChoicePicker(title: "", selection: policy(\.refreshInterval), options: [("manual", "Manual"), ("daily", "Daily"), ("weekly", "Weekly")]).font(.subheadline)
                }
                if mediaID != "0" {
                    GeneralStyle.divider
                    row("Pause updates", detail: "Suspend scheduled refreshes for this series.", value: policy(\.pauseUpdates))
                    GeneralStyle.divider
                    GeneralRow("Use global defaults", detail: "Remove this series’ custom rules.") {
                        Button("Reset") { Task { await model.resetSeries(mediaID) } }.buttonStyle(GeneralTextButtonStyle())
                    }
                }
            }
            GeneralSection("Custom overrides") {
                GeneralRow("Per-series rules", detail: "Reset saved overrides to the global defaults.") {
                    Button("Reset") { reset = true }.buttonStyle(GeneralTextButtonStyle())
                }
            }
        }.disabled(!model.loaded || model.busy)
            .overlay { if model.busy && !model.loaded { ProgressView() } }
            .task { await library.load() }
            .task(id: mediaID) { await model.load(mediaID: mediaID) }
        if let notice = model.notice {
            GeneralRow(notice, detail: "") { Button("Retry") { Task { await model.load(mediaID: mediaID) } }.buttonStyle(GeneralTextButtonStyle()) }
        }
        // The server persists schedules; iOS controls when the application can execute them.
        EmptyView().confirmationDialog("Reset all custom rules?", isPresented: $reset, titleVisibility: .visible) {
            Button("Reset rules", role: .destructive) { Task { await model.resetOverrides() } }
        }
    }
    private func row(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        GeneralRow(title, detail: detail) { Toggle(title, isOn: value).toggleStyle(GeneralToggleStyle()) }
    }
    private func number(_ title: String, detail: String, value: Binding<Int>, options: [Int]) -> some View {
        GeneralRow(title, detail: detail) {
            ChoicePicker(title: "", selection: value, options: Array(Set(options + [value.wrappedValue])).sorted().map { ($0, String($0)) }).font(.subheadline)
        }
    }
}

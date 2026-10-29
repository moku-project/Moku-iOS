import SwiftUI

struct DownloadPolicy: Codable, Equatable, Sendable {
    var pauseUpdates = false
    var refreshInterval = "manual"
    var autoDownload = false
    var downloadAhead = 0
    var deleteOnRead = false
    var deleteDelayHours = 0
    var maxKeepChapters = 0
    var autoDownloadScanlators: [String]?
}
struct AutomationControls: Codable, Sendable {
    var enabled = true
    var enforceGlobal = false
}
@MainActor @Observable final class AutomationPreferences {
    var policy = DownloadPolicy()
    var controls = AutomationControls()
    var loaded = false
    var busy = false
    var notice: String?
    func load(mediaID: String = "0") async {
        busy = true
        defer { busy = false }
        do {
            policy = try JSONDecoder().decode(DownloadPolicy.self, from: await BackendAPI.shared.api(path: "/api/mobile/automation?mediaId=\(mediaID)"))
            controls = try JSONDecoder().decode(AutomationControls.self, from: await BackendAPI.shared.api(path: "/api/mobile/automation-controls"))
            loaded = true
            notice = nil
        } catch { notice = "Couldn’t load automation settings. Try again." }
    }
    func savePolicy(_ value: DownloadPolicy, mediaID: String = "0") async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await BackendAPI.shared.api(path: "/api/mobile/automation?mediaId=\(mediaID)", method: "PUT", body: JSONEncoder().encode(value))
            policy = value
            notice = nil
        } catch { notice = "Couldn’t save automation rules." }
    }
    func saveControls(_ value: AutomationControls) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await BackendAPI.shared.api(path: "/api/mobile/automation-controls", method: "PUT", body: JSONEncoder().encode(value))
            controls = value
            notice = nil
        } catch { notice = "Couldn’t save automation controls." }
    }
    func resetSeries(_ mediaID: String) async {
        guard !busy else { return }
        do {
            _ = try await BackendAPI.shared.api(path: "/api/mobile/automation?mediaId=\(mediaID)", method: "DELETE")
            await load(mediaID: mediaID)
        } catch { notice = "Couldn’t reset series rules." }
    }
    func resetOverrides() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await BackendAPI.shared.api(path: "/api/mobile/automation-controls", method: "DELETE")
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
    @State private var scanlators = ""
    @State private var editingScanlators = false
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
    @AppStorage("automation.updateOnOpen") private var updateOnOpen = false
    @AppStorage("automation.backgroundUpdates") private var backgroundUpdates = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GeneralSection("Library updates") {
                GeneralRow("Update library on app open", detail: "Check every saved series for new chapters when Moku starts. Results appear in Recent → Updates.") {
                    Toggle("Update library on app open", isOn: $updateOnOpen).toggleStyle(GeneralToggleStyle())
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
                GeneralStyle.divider
                row("Pause updates", detail: "Suspend scheduled series refreshes.", value: policy(\.pauseUpdates))
                GeneralStyle.divider
                GeneralRow("Scanlators", detail: model.policy.autoDownloadScanlators?.joined(separator: ", ") ?? "Download from all groups.") {
                    Button("Edit") {
                        scanlators = model.policy.autoDownloadScanlators?.joined(separator: ", ") ?? ""
                        editingScanlators = true
                    }.buttonStyle(GeneralTextButtonStyle())
                }
                if mediaID != "0" {
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
            .alert("Scanlators", isPresented: $editingScanlators) {
                TextField("Names, separated by commas", text: $scanlators)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    var next = model.policy
                    next.autoDownloadScanlators = Array(Set(scanlators.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
                    Task { await model.savePolicy(next, mediaID: mediaID) }
                }
            } message: { Text("Leave blank to allow all groups.") }
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

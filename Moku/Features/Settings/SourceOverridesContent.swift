import SwiftUI

struct SourceOverrides: Codable, Sendable {
    var enabled = false
    var allowed: [Int64]?
    var blocked: [Int64]?
}
struct SourceOverridesContent: View {
    struct Source: Decodable, Identifiable, Sendable { let id: String; let displayName: String; let lang: String }
    @State private var value = SourceOverrides()
    @State private var sources: [Source] = []
    @State private var filter = ""
    @State private var busy = false
    @State private var loaded = false
    @State private var notice: String?
    var body: some View {
        GeneralSection("Source overrides") {
            GeneralRow("Per-source overrides", detail: "Allow or block a specific source.") {
                Toggle("Per-source overrides", isOn: Binding(get: { value.enabled }, set: { enabled in
                    var next = value; next.enabled = enabled; save(next)
                })).toggleStyle(GeneralToggleStyle()).disabled(!loaded || busy)
            }
            if value.enabled {
                GeneralStyle.divider
                TextField("Filter sources", text: $filter).generalInput()
                ForEach(sources.filter { filter.isEmpty || $0.displayName.localizedCaseInsensitiveContains(filter) }) { source in
                    GeneralRow(source.displayName, detail: GeneralPreferences.languageName(GeneralPreferences.canonicalLanguage(source.lang))) {
                        ChoicePicker(title: "", selection: Binding(get: { decision(source.id) }, set: { choice in
                            guard let id = Int64(source.id) else { return }
                            var next = value
                            next.allowed = (next.allowed ?? []).filter { $0 != id }
                            next.blocked = (next.blocked ?? []).filter { $0 != id }
                            if choice == "allow" { next.allowed?.append(id) }
                            if choice == "block" { next.blocked?.append(id) }
                            save(next)
                        }), options: [("default", "Default"), ("allow", "Allow"), ("block", "Block")]).font(.subheadline)
                    }.disabled(busy)
                    GeneralStyle.divider
                }
                if sources.isEmpty { Text("No sources installed.").font(.footnote).foregroundStyle(GeneralStyle.faint).padding(.vertical, 14) }
            }
            if let notice {
                GeneralRow(notice, detail: "") { Button("Retry") { Task { await load() } }.buttonStyle(GeneralTextButtonStyle()) }
            }
        }.task { await load() }
    }
    private func decision(_ source: String) -> String {
        guard let id = Int64(source) else { return "default" }
        if value.blocked?.contains(id) == true { return "block" }
        if value.allowed?.contains(id) == true { return "allow" }
        return "default"
    }
    private func load() async {
        busy = true
        defer { busy = false }
        do {
            struct Result: Decodable, Sendable { let installedExtensions: [Source] }
            let result: Result = try await BackendAPI.shared.graphql("{ installedExtensions { id displayName lang } }", requiresSourceRuntime: false)
            value = try JSONDecoder().decode(SourceOverrides.self, from: await BackendAPI.shared.api(path: "/api/mobile/source-overrides"))
            sources = result.installedExtensions.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            loaded = true; notice = nil
        } catch { notice = "Couldn’t load source overrides." }
    }
    private func save(_ next: SourceOverrides) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try await BackendAPI.shared.api(path: "/api/mobile/source-overrides", method: "PUT", body: JSONEncoder().encode(next))
                value = next; notice = nil
                await BackendAPI.shared.clearContentCache()
                NotificationCenter.default.post(name: .contentVisibilityDidChange, object: nil)
            } catch { notice = "Couldn’t save source overrides." }
        }
    }
}

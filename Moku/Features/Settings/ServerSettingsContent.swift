import SwiftUI

struct ServerSettingsContent: View {
    @State private var model = ServerPreferences()
    let openExtensions: () -> Void
    private let groups: [(String, [String])] = [
        ("Cloudflare", ["cloudflare_solver_mode", "cloudflare_solver_url"]),
        ("Features", ["novel_enabled", "metadata_backfill", "idle_timeout_minutes", "tracker_poll_hours"]),
        ("Integrations", ["public_url", "anilist_client_id", "mal_client_id", "mal_client_secret"]),
        ("Directories", ["media_dir", "jar_cache_dir", "downloads_dir", "local_source_dir", "sandbox_extensions_dir", "sandbox_storage_dir"]),
        ("Sandbox", ["sandbox_heap_mb", "sandbox_addr", "sandbox_port"]),
        ("Backups", ["backup_interval_hours", "backup_retention_count"]),
        ("Diagnostics", ["pprof_addr"]),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GeneralSettingsView(openExtensions: openExtensions, serverOnly: true)
            if model.loading && model.values.isEmpty { ProgressView().frame(maxWidth: .infinity, minHeight: 44) }
            ForEach(groups, id: \.0) { title, keys in
                let rows = model.values.filter { $0.editable && keys.contains($0.key) }
                if !rows.isEmpty {
                    GeneralSection(title) {
                        ForEach(rows) { setting in
                            ServerPreferenceRow(setting: setting, model: model)
                            if setting.id != rows.last?.id { GeneralStyle.divider }
                        }
                    }
                }
            }
            let known = Set(groups.flatMap(\.1))
            let advanced = model.values.filter { $0.editable && !known.contains($0.key) }
            if !advanced.isEmpty {
                GeneralSection("Advanced") {
                    ForEach(advanced) { setting in
                        ServerPreferenceRow(setting: setting, model: model)
                        if setting.id != advanced.last?.id { GeneralStyle.divider }
                    }
                }
            }
            let readOnly = model.values.filter { !$0.editable && $0.key != "api_token" }
            if !readOnly.isEmpty {
                GeneralSection("Read-only") {
                    ForEach(readOnly) { setting in
                        ServerPreferenceRow(setting: setting, model: model)
                        if setting.id != readOnly.last?.id { GeneralStyle.divider }
                    }
                }
            }
            if let notice = model.notice {
                GeneralRow(notice, detail: "") {
                    Button("Retry") { Task { await model.load() } }.buttonStyle(GeneralTextButtonStyle())
                }
            }
        }.task { await model.load() }
    }
}

struct ServerPreferenceRow: View {
    let setting: ServerPreference
    @Bindable var model: ServerPreferences
    @State private var draft = ""
    var body: some View {
        GeneralRow(setting.label, detail: setting.description) {
            if !setting.editable {
                Text(setting.value.isEmpty ? "—" : setting.value).font(.system(size: 14))
                    .foregroundStyle(GeneralStyle.text).multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            } else if setting.type == "BOOL" {
                Toggle(setting.label, isOn: Binding(get: { setting.value == "true" }, set: { value in
                    Task { await model.save(setting, value: String(value)) }
                })).toggleStyle(GeneralToggleStyle())
            } else if !setting.choices.isEmpty {
                ChoicePicker(title: "", selection: Binding(get: { setting.value }, set: { value in
                    Task { await model.save(setting, value: value) }
                }), options: setting.choices).font(.system(size: 14)).accessibilityLabel(setting.label)
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    Group {
                        if setting.key.contains("secret") { SecureField(setting.label, text: $draft) }
                        else { TextField(setting.label, text: $draft).keyboardType(setting.type == "INT" ? .numberPad : .default) }
                    }.textInputAutocapitalization(.never).autocorrectionDisabled().generalInput().frame(width: 150)
                    Button("Save") { Task { await model.save(setting, value: draft) } }
                        .buttonStyle(GeneralTextButtonStyle()).disabled(draft == setting.value)
                }
            }
        }.disabled(model.saving)
            .onAppear { draft = setting.value }
            .onChange(of: setting.value) { _, value in draft = value }
    }
}

struct ContentSettingsContent: View {
    @State private var server = ServerPreferences()
    @State private var model = ContentRules()
    @State private var keyword = ""
    @State private var category = "Custom"
    @State private var field = "TAG"
    @State private var level = "MODERATE"
    @State private var weight = 0
    @State private var confirmingReset = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SourceOverridesContent()
            GeneralSection("Content level") {
                if let value = server.values.first(where: { $0.key == "content_filter_level" }) {
                    ServerPreferenceRow(setting: value, model: server)
                } else if server.loading { ProgressView().frame(minHeight: 44) }
                if let notice = server.notice { Text(notice).font(.system(size: 13)).foregroundStyle(GeneralStyle.faint) }
            }
            GeneralSection("Add rule") {
                GeneralRow("Category", detail: "") { TextField("Category", text: $category).generalInput().frame(width: 150) }
                GeneralStyle.divider
                GeneralRow("Keyword", detail: "") { TextField("Keyword", text: $keyword).generalInput().frame(width: 150) }
                GeneralStyle.divider
                GeneralRow("Field", detail: "") {
                    ChoicePicker(title: "", selection: $field, options: ["GENRE", "TAG", "TITLE", "DESCRIPTION"].map { ($0, $0.capitalized) }).font(.system(size: 14))
                }
                GeneralStyle.divider
                GeneralRow("Block level", detail: "") {
                    ChoicePicker(title: "", selection: $level, options: [("MODERATE", "Moderate"), ("STRICT", "Strict")]).font(.system(size: 14))
                }
                GeneralStyle.divider
                GeneralRow("Minimum weight", detail: "Tag weight from 0 to 100.") {
                    ChoicePicker(title: "", selection: $weight, options: stride(from: 0, through: 100, by: 10).map { ($0, String($0)) }).font(.system(size: 14))
                }
                GeneralRow("Content rule", detail: "") {
                    Button("Add") { Task {
                        await model.add(category: category, field: field, keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines), weight: weight, level: level)
                        if model.notice == nil { keyword = "" }
                    }}.buttonStyle(GeneralTextButtonStyle()).disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
                }
            }
            GeneralSection("Rules") {
                ForEach(model.rules) { rule in
                    GeneralRow(rule.keyword, detail: "\(rule.field.capitalized) · \(rule.blockLevel.capitalized) · \(rule.minWeight)") {
                        Button("Remove") { Task { await model.change("removeContentFilterRule(id: \(BackendAPI.literal(rule.id)))") } }.buttonStyle(GeneralTextButtonStyle())
                    }
                    GeneralStyle.divider
                }
                GeneralRow("Reclassify library", detail: "Apply current rules to saved metadata.") {
                    Button("Run") { Task { await model.change("recomputeContentFilter") } }.buttonStyle(GeneralTextButtonStyle())
                }
                GeneralStyle.divider
                GeneralRow("Default rules", detail: "Restore the built-in rule set.") {
                    Button("Reset") { confirmingReset = true }.buttonStyle(GeneralTextButtonStyle())
                }
            }.disabled(model.busy)
            if let notice = model.notice { Text(notice).font(.system(size: 13)).foregroundStyle(GeneralStyle.faint) }
        }.task { await server.load(); await model.load() }
            .confirmationDialog("Reset content rules?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset rules", role: .destructive) { Task { await model.change("resetContentFilterRules") } }
            }
    }
}

import SwiftUI

struct ServerSettingsContent: View {
    @State private var model = ServerPreferences()
    @State private var logOpen = false
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
        SettingsForm {
            BundledServerSection()
            Section {
                SettingsLinkRow("Server log", detail: "Recent output from the bundled server, for troubleshooting sources.") { logOpen = true }
                    .accessibilityIdentifier("server.log.open")
            } header: {
                Text("Logs")
            }
            if model.loading && model.values.isEmpty {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
            ForEach(groups, id: \.0) { title, keys in
                let rows = model.values.filter { $0.editable && keys.contains($0.key) }
                if !rows.isEmpty {
                    Section(title) {
                        ForEach(rows) { setting in ServerPreferenceRow(setting: setting, model: model) }
                    }
                }
            }
            let known = Set(groups.flatMap(\.1))
            let advanced = model.values.filter { $0.editable && !known.contains($0.key) }
            if !advanced.isEmpty {
                Section("Advanced") {
                    ForEach(advanced) { setting in ServerPreferenceRow(setting: setting, model: model) }
                }
            }
            let readOnly = model.values.filter { !$0.editable && $0.key != "api_token" }
            if !readOnly.isEmpty {
                Section("Read-only") {
                    ForEach(readOnly) { setting in ServerPreferenceRow(setting: setting, model: model) }
                }
            }
            SettingsNotice(text: model.notice) { Task { await model.load() } }
        }
        .task { await model.load() }
        .sheet(isPresented: $logOpen) { ServerLogView() }
    }
}

struct ServerPreferenceRow: View {
    let setting: ServerPreference
    @Bindable var model: ServerPreferences
    @State private var draft = ""
    var body: some View {
        Group {
            if !setting.editable {
                LabeledContent {
                    Text(setting.value.isEmpty ? "—" : setting.value)
                        .multilineTextAlignment(.trailing).textSelection(.enabled)
                } label: {
                    SettingsLabel(setting.label, detail: setting.description)
                }
            } else if setting.type == "BOOL" {
                SettingsToggle(setting.label, detail: setting.description, isOn: Binding(get: { setting.value == "true" }, set: { value in
                    Task { await model.save(setting, value: String(value)) }
                }))
            } else if !setting.choices.isEmpty {
                SettingsPicker(setting.label, detail: setting.description, selection: Binding(get: { setting.value }, set: { value in
                    Task { await model.save(setting, value: value) }
                }), options: setting.choices)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsLabel(setting.label, detail: setting.description)
                    HStack {
                        Group {
                            if setting.key.contains("secret") { SecureField(setting.label, text: $draft) }
                            else { TextField(setting.label, text: $draft).keyboardType(setting.type == "INT" ? .numberPad : .default) }
                        }
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        Button("Save") { Task { await model.save(setting, value: draft) } }
                            .buttonStyle(.borderless)
                            .disabled(draft == setting.value)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .disabled(model.saving)
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
        SettingsForm {
            Section("Content level") {
                if let value = server.values.first(where: { $0.key == "content_filter_level" }) {
                    ServerPreferenceRow(setting: value, model: server)
                } else if server.loading {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if let notice = server.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                LabeledContent("Category") {
                    TextField("Category", text: $category).multilineTextAlignment(.trailing)
                }
                LabeledContent("Keyword") {
                    TextField("Keyword", text: $keyword).multilineTextAlignment(.trailing)
                }
                SettingsPicker("Field", selection: $field, options: ["GENRE", "TAG", "TITLE", "DESCRIPTION"].map { ($0, $0.capitalized) })
                SettingsPicker("Block level", selection: $level, options: [("MODERATE", "Moderate"), ("STRICT", "Strict")])
                Stepper(value: $weight, in: 0...100, step: 10) {
                    LabeledContent("Minimum weight", value: String(weight))
                }
                Button("Add rule") { Task {
                    await model.add(category: category, field: field, keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines), weight: weight, level: level)
                    if model.notice == nil { keyword = "" }
                }}
                .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
            } header: {
                Text("Add rule")
            } footer: {
                Text("Minimum weight is the tag weight from 0 to 100.")
            }
            Section("Rules") {
                ForEach(model.rules) { rule in
                    SettingsLabel(rule.keyword, detail: "\(rule.field.capitalized) · \(rule.blockLevel.capitalized) · \(rule.minWeight)")
                        .swipeActions {
                            Button("Remove", role: .destructive) { remove(rule.id) }
                        }
                        .contextMenu {
                            Button("Remove", systemImage: "trash", role: .destructive) { remove(rule.id) }
                        }
                }
            }
            .disabled(model.busy)
            Section {
                Button {
                    Task { await model.change("recomputeContentFilter") }
                } label: {
                    SettingsLabel("Reclassify library", detail: "Apply current rules to saved metadata.")
                }
                Button("Restore default rules", role: .destructive) { confirmingReset = true }
            }
            .disabled(model.busy)
            SettingsNotice(text: model.notice)
        }
        .task { await server.load(); await model.load() }
        .confirmationDialog("Reset content rules?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset rules", role: .destructive) { Task { await model.change("resetContentFilterRules") } }
        }
    }
    private func remove(_ id: String) {
        Task { await model.change("removeContentFilterRule(id: \(BackendAPI.literal(id)))") }
    }
}

import SwiftUI

struct SourceSettingsView: View {
    let source: SourceExtension
    let repository: any ExtensionRepository
    @Environment(\.dismiss) private var dismiss
    @State private var preferences: [SourcePreference] = []
    @State private var editing: SourcePreference?
    @State private var busy = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if busy && preferences.isEmpty { ContentSkeleton(style: .settings) }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Button("Retry") { Task { await load() } }
                    }
                }
                if preferences.isEmpty && !busy && error == nil {
                    ContentUnavailableView(
                        "No Source Settings", systemImage: "slider.horizontal.3",
                        description: Text("This extension does not expose configurable settings."))
                }
                ForEach(preferences) { preference in
                    Button {
                        editing = preference
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preference.title).foregroundStyle(.primary)
                                if !preference.summary.isEmpty {
                                    Text(preference.displaySummary).font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary).accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .firstLoadSkeleton("source-settings-\(source.id)", loading: busy, style: .settings)
            .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle(source.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
            .sheet(item: $editing) { preference in
                PreferenceEditor(preference: preference) { value in
                    preferences = try await repository.savePreference(
                        package: source.packageName, key: preference.key, value: value)
                }
            }
        }
    }
    private func load() async {
        busy = true
        defer { busy = false }
        do {
            preferences = try await repository.preferences(package: source.packageName)
            error = nil
        } catch { self.error = "Couldn’t load source settings. Try again." }
    }
}

private struct PreferenceEditor: View {
    let preference: SourcePreference
    let save: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                switch preference.type {
                case "SWITCH":
                    Toggle(
                        preference.title,
                        isOn: Binding(
                            get: { value == "true" }, set: { value = $0 ? "true" : "false" }))
                case "LIST":
                    ChoicePicker(
                        title: preference.title, selection: $value,
                        options: preference.entryValues.enumerated().map { index, option in
                            (
                                option,
                                index < preference.entries.count
                                    ? preference.entries[index] : option
                            )
                        })
                case "MULTI_SELECT":
                    ForEach(Array(preference.entryValues.enumerated()), id: \.offset) {
                        index, option in
                        Toggle(
                            index < preference.entries.count ? preference.entries[index] : option,
                            isOn: Binding(
                                get: { selected.contains(option) },
                                set: { enabled in
                                    var values = selected
                                    if enabled {
                                        values.insert(option)
                                    } else {
                                        values.remove(option)
                                    }
                                    value = String(
                                        decoding: (try? JSONEncoder().encode(values.sorted()))
                                            ?? Data(), as: UTF8.self)
                                }))
                    }
                default:
                    TextField(preference.title, text: $value, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    Button("Restore Default") { value = preference.defaultValue }
                } footer: {
                    if !preference.summary.isEmpty { Text(preference.displaySummary) }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .navigationTitle(preference.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Save") {
                        Task {
                            busy = true
                            defer { busy = false }
                            do {
                                try await save(value)
                                dismiss()
                            } catch { self.error = "Couldn’t save this setting. Try again." }
                        }
                    } }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .interactiveDismissDisabled(busy)
        }.onAppear { value = preference.currentValue }
    }
    private var selected: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(value.utf8))) ?? [])
    }
}

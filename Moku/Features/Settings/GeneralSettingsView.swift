import SwiftUI

/// Settings › General as a native Form.
struct GeneralSettingsView: View {
    @AppStorage("preferences.startTab") private var startTab = AppTab.library.rawValue
    let openExtensions: () -> Void
    @AppStorage("preferences.interfaceScale") private var scale = 100.0
    @AppStorage("preferences.idleTimeout") private var idleTimeout = 5
    @AppStorage("preferences.animations") private var animations = true
    @AppStorage("preferences.language") private var language = "all"

    var body: some View {
        SettingsForm {
            Section {
                Stepper {
                    LabeledContent("Interface scale") {
                        Text("\(Int(GeneralPreferences.clampedScale(scale)))%")
                            .monospacedDigit()
                            .accessibilityIdentifier("settings.general.scaleValue")
                    }
                } onIncrement: {
                    scale = GeneralPreferences.clampedScale(scale + 5)
                } onDecrement: {
                    scale = GeneralPreferences.clampedScale(scale - 5)
                }
                .accessibilityIdentifier("settings.general.scale")
                Button("Reset to 100%") { scale = 100 }
                    .disabled(scale == 100)
                    .accessibilityLabel("Reset interface scale")
            } header: {
                Text("Interface")
            } footer: {
                Text("Adjust the size of the app. Reader zoom is separate.")
            }
            BundledServerSection()
            Section("Startup") {
                SettingsPicker(
                    "Default view", detail: "The tab Moku opens to.", selection: $startTab,
                    options: AppTab.startChoices.map { ($0.rawValue, $0.title) })
            }
            Section {
                SettingsPicker(
                    "Idle screen timeout", selection: $idleTimeout,
                    options: [0, 1, 2, 5, 10, 15, 30].map { ($0, GeneralPreferences.timeoutLabel($0)) },
                    identifier: "settings.general.idleTimeout")
            } header: {
                Text("Inactivity")
            } footer: {
                Text("Show the Moku idle screen after this much inactivity. Paused while reading or playing media.")
            }
            Section("Animations") {
                SettingsToggle(
                    "Interface animations",
                    detail: "Tab transitions and button feedback. Respects Reduce Motion.",
                    isOn: $animations)
            }
            Section {
                SettingsPicker(
                    "Preferred source language",
                    selection: Binding(
                        get: { GeneralPreferences.canonicalLanguage(language) },
                        set: { language = $0 }),
                    options: GeneralPreferences.languageOptions(including: language),
                    identifier: "settings.general.language")
                    .pickerStyle(.navigationLink)
            } header: {
                Text("Language")
            } footer: {
                Text("\(GeneralPreferences.languageName(language)), pre-selected in Search.")
            }
            Section {
                SettingsLinkRow("Extensions and sources", systemImage: "puzzlepiece.extension", action: openExtensions)
                    .accessibilityIdentifier("settings.general.extensions")
            } header: {
                Text("Extensions")
            } footer: {
                Text("Browse extensions and manage installed sources.")
            }
        }
    }
}

/// Status and startup of the embedded server. Shown in General and Server.
struct BundledServerSection: View {
    // The embedded server runs once per app process.
    @AppStorage(
        "backend.autoStart",
        store: PreviewMode.isEnabled
            ? UserDefaults(suiteName: "Moku.Previews.Settings")! : .standard
    ) private var autoStart = true
    @State private var serverURL: String?
    @State private var starting = false
    @State private var serverError: String?

    var body: some View {
        Section {
            // The loopback address changes each launch and is app-private, so describe it instead of showing it.
            LabeledContent("Bundled server") {
                Text(serverURL == nil ? "Not started" : "Running")
                    .foregroundStyle(serverURL == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(NavigationStyle.accent))
            }
            .task {
                guard !PreviewMode.isEnabled else { return }
                serverURL = await Backend.shared.currentServerURL()?.absoluteString
            }
            SettingsToggle(
                "Auto-start bundled server",
                detail: "Start when a feature needs it. Turning this off takes effect on the next app launch.",
                isOn: $autoStart)
            if serverURL == nil {
                Button {
                    Task {
                        starting = true
                        defer { starting = false }
                        do {
                            serverURL = try await Backend.shared.connection(
                                requiresSourceRuntime: false, manualStart: true
                            ).baseURL.absoluteString
                            serverError = nil
                        } catch { serverError = error.localizedDescription }
                    }
                } label: {
                    HStack {
                        Text(starting ? "Starting…" : "Start server")
                        if starting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(starting)
            }
        } header: {
            Text("Server")
        } footer: {
            Text(serverError ?? (serverURL == nil
                ? "Runs privately on this device. Start it manually when automatic startup is off."
                : "Runs privately on this device. Sources and downloads go through it."))
        }
    }
}

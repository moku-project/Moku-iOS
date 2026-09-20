import SwiftUI

/// Open, readable settings sections using the app’s native navigation and controls.
struct GeneralSettingsView: View {
    let openExtensions: () -> Void
    var serverOnly = false
    @AppStorage("preferences.interfaceScale") private var scale = 100.0
    @AppStorage("preferences.idleTimeout") private var idleTimeout = 5
    @AppStorage("preferences.animations") private var animations = true
    @AppStorage("preferences.language") private var language = "all"
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
        VStack(alignment: .leading, spacing: 20) {
            if !serverOnly {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Interface scale")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GeneralStyle.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("Adjust the size of the app. Reader zoom is separate.")
                        .font(.system(size: 13)).foregroundStyle(GeneralStyle.faint)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button {
                            scale = GeneralPreferences.clampedScale(scale - 5)
                        } label: {
                            PhosphorIcon("Minus", size: 18)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .disabled(scale <= 50)
                        .accessibilityLabel("Decrease interface scale")
                        .accessibilityIdentifier("settings.general.scale.decrease")
                        Text("\(Int(GeneralPreferences.clampedScale(scale)))%")
                            .font(.system(size: 18, weight: .medium)).monospacedDigit()
                            .foregroundStyle(GeneralStyle.text)
                            .frame(minWidth: 54)
                            .accessibilityIdentifier("settings.general.scaleValue")
                        Button {
                            scale = GeneralPreferences.clampedScale(scale + 5)
                        } label: {
                            PhosphorIcon("Plus", size: 18)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .disabled(scale >= 200)
                        .accessibilityLabel("Increase interface scale")
                        .accessibilityIdentifier("settings.general.scale.increase")
                        Spacer(minLength: 0)
                        Button {
                            scale = 100
                        } label: {
                            PhosphorIcon("ArrowCounterClockwise", size: 18)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .disabled(scale == 100)
                        .accessibilityLabel("Reset interface scale")
                    }
                    .buttonStyle(.plain).foregroundStyle(GeneralStyle.label)
                    GeneralStyle.divider.padding(.top, 14)
                }
            }
            GeneralSection("Server") {
                GeneralRow("Server URL", detail: "Address of the bundled server on this device.") {
                    Text(serverURL ?? "On this iPhone")
                        .font(.system(size: 14)).foregroundStyle(GeneralStyle.text).textSelection(
                            .enabled
                        )
                        .multilineTextAlignment(.trailing).frame(maxWidth: 130)
                }
                GeneralStyle.divider
                GeneralRow(
                    "Auto-start bundled server",
                    detail:
                        "Start when a feature needs it. Turning this off takes effect on the next app launch."
                ) {
                    Toggle("Auto-start bundled server", isOn: $autoStart).toggleStyle(
                        GeneralToggleStyle())
                }
                if serverURL == nil {
                    GeneralStyle.divider
                    GeneralRow(
                        "Bundled server",
                        detail: serverError ?? "Start manually when automatic startup is off."
                    ) {
                        Button(starting ? "Starting…" : "Start") {
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
                        }.buttonStyle(GeneralButtonStyle()).disabled(starting)
                    }
                }
            }
            if !serverOnly {
                GeneralSection("Inactivity") {
                    GeneralRow(
                        "Idle screen timeout",
                        detail:
                            "Show the Moku idle screen after this much inactivity. Paused while reading or playing media."
                    ) {
                        ChoicePicker(
                            title: "", selection: $idleTimeout,
                            options: [0, 1, 2, 5, 10, 15, 30].map {
                                ($0, GeneralPreferences.timeoutLabel($0))
                            }
                        )
                        .font(.system(size: 14))
                        .accessibilityLabel("Idle screen timeout")
                        .accessibilityValue(GeneralPreferences.timeoutLabel(idleTimeout))
                        .accessibilityIdentifier("settings.general.idleTimeout")
                    }
                }
                GeneralSection("Animations") {
                    GeneralRow(
                        "Interface animations",
                        detail: "Tab transitions and button feedback. Respects Reduce Motion."
                    ) {
                        Toggle("Interface animations", isOn: $animations).toggleStyle(
                            GeneralToggleStyle()
                        )
                        .accessibilityIdentifier("Interface animations")
                    }
                }
                GeneralSection("Language") {
                    GeneralRow(
                        "Preferred source language",
                        detail:
                            "\(GeneralPreferences.languageName(language)), pre-selected in Search."
                    ) {
                        ChoicePicker(
                            title: "",
                            selection: Binding(
                                get: { GeneralPreferences.canonicalLanguage(language) },
                                set: { language = $0 }),
                            options: GeneralPreferences.languageOptions(including: language)
                        )
                        .font(.system(size: 14)).frame(maxWidth: 160)
                        .accessibilityLabel("Preferred source language")
                        .accessibilityIdentifier("settings.general.language")
                    }
                }
                GeneralSection("Extensions") {
                    GeneralRow(
                        "Extensions and sources",
                        detail: "Browse extensions and manage installed sources."
                    ) {
                        Button("Manage", action: openExtensions).buttonStyle(
                            GeneralTextButtonStyle()
                        )
                        .accessibilityIdentifier("settings.general.extensions")
                    }
                }
            }
        }
        .task {
            guard !PreviewMode.isEnabled else { return }
            serverURL = await Backend.shared.currentServerURL()?.absoluteString
        }
    }

}

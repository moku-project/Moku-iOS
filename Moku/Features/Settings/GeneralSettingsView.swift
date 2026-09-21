import SwiftUI

/// Desktop General's panel structure, using the app's system typography.
struct GeneralSettingsView: View {
    let openExtensions: () -> Void
    @AppStorage("preferences.interfaceScale") private var scale = 100.0
    @AppStorage("preferences.idleTimeout") private var idleTimeout = 5
    @AppStorage("preferences.animations") private var animations = true
    @AppStorage("preferences.language") private var language = "all"
    // The embedded server is shared by every profile.
    @AppStorage("backend.autoStart", store: .standard) private var autoStart = true
    @State private var languageDraft = ""
    @State private var scaleDraft = "100"
    @State private var serverURL: String?
    @State private var starting = false
    @State private var serverError: String?
    @FocusState private var focused: Field?
    private enum Field { case language, scale }

    var body: some View {
        VStack(spacing: 8) {
            GeneralPanel("Interface scale") {
                Text(
                    "Fits your screen automatically. 100% is the default; adjust to taste. The reader has its own zoom."
                )
                .font(.system(size: 11)).foregroundStyle(GeneralStyle.faint)
                .padding(.horizontal, 16).padding(.top, 8)
                HStack(spacing: 12) {
                    Slider(value: $scale, in: 50...200, step: 5)
                        .tint(NavigationStyle.accent).accessibilityLabel("Interface scale")
                        .accessibilityIdentifier("settings.general.scale")
                    TextField("100", text: $scaleDraft)
                        .keyboardType(.numberPad).multilineTextAlignment(.center)
                        .focused($focused, equals: .scale)
                        .generalInput().frame(width: 42)
                        .accessibilityLabel("Interface scale percentage")
                    Text("%").font(.system(size: 11)).foregroundStyle(GeneralStyle.faint)
                    Button {
                        focused = nil
                        scale = 100
                        scaleDraft = "100"
                    } label: {
                        PhosphorIcon("ArrowCounterClockwise", size: 14).frame(width: 28, height: 44)
                    }.buttonStyle(.plain).disabled(scale == 100)
                        .accessibilityLabel("Reset interface scale")
                }.padding(.horizontal, 16).padding(.vertical, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 43), spacing: 4)], spacing: 4) {
                    ForEach([50, 60, 70, 80, 90, 100, 110, 125, 150, 175, 200], id: \.self) {
                        value in
                        Button {
                            focused = nil
                            scale = Double(value)
                        } label: {
                            Text("\(value)%").font(.system(size: 10))
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(
                                    scale == Double(value)
                                        ? NavigationStyle.accent.opacity(0.14) : .clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3).strokeBorder(
                                        scale == Double(value)
                                            ? NavigationStyle.accent.opacity(0.4)
                                            : GeneralStyle.border))
                        }.buttonStyle(.plain)
                            .foregroundStyle(
                                scale == Double(value) ? NavigationStyle.accent : GeneralStyle.faint
                            )
                            .accessibilityIdentifier("settings.general.scale.\(value)")
                    }
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }
            GeneralPanel("Server") {
                GeneralRow("Server URL", detail: "Address of the bundled server on this device.") {
                    Text(serverURL ?? "On this iPhone")
                        .font(.system(size: 11)).textSelection(.enabled)
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
            GeneralPanel("Inactivity") {
                GeneralRow(
                    "Idle screen timeout",
                    detail:
                        "Show the Moku idle screen after this much inactivity. Paused while reading or playing media."
                ) {
                    Menu {
                        ForEach([0, 1, 2, 5, 10, 15, 30], id: \.self) { minutes in
                            Button(GeneralPreferences.timeoutLabel(minutes)) {
                                idleTimeout = minutes
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(GeneralPreferences.timeoutLabel(idleTimeout))
                            PhosphorIcon("CaretDown", size: 10)
                        }
                    }.buttonStyle(GeneralButtonStyle())
                        .accessibilityLabel("Idle screen timeout")
                        .accessibilityValue(GeneralPreferences.timeoutLabel(idleTimeout))
                        .accessibilityIdentifier("settings.general.idleTimeout")
                }
            }
            GeneralPanel("Animations") {
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
            GeneralPanel("Language") {
                GeneralRow(
                    "Preferred source language",
                    detail: "\(GeneralPreferences.languageName(language)), pre-selected in Search."
                ) {
                    TextField("All", text: $languageDraft)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .multilineTextAlignment(.center).submitLabel(.done)
                        .focused($focused, equals: .language)
                        .generalInput().frame(width: 88)
                        .accessibilityLabel("Preferred source language")
                        .accessibilityIdentifier("settings.general.language")
                        .onSubmit {
                            commitLanguage()
                            focused = nil
                        }
                }
            }
            GeneralPanel("Extensions") {
                GeneralRow(
                    "Extensions and sources",
                    detail: "Browse extensions and manage installed sources."
                ) {
                    Button("Manage", action: openExtensions).buttonStyle(GeneralButtonStyle())
                        .accessibilityIdentifier("settings.general.extensions")
                }
            }
        }
        .onAppear {
            languageDraft = language == "all" ? "All" : language
            scaleDraft = String(Int(GeneralPreferences.clampedScale(scale)))
        }
        .onChange(of: scale) { _, value in
            scaleDraft = String(Int(GeneralPreferences.clampedScale(value)))
        }
        .onChange(of: focused) { old, _ in
            if old == .language { commitLanguage() }
            if old == .scale {
                scale = GeneralPreferences.clampedScale(Double(scaleDraft) ?? 100)
                scaleDraft = String(Int(scale))
            }
        }
        .onDisappear { commitLanguage() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .task { serverURL = await Backend.shared.currentServerURL()?.absoluteString }
    }

    private func commitLanguage() {
        language = GeneralPreferences.canonicalLanguage(languageDraft)
        languageDraft = language == "all" ? "All" : language
    }
}

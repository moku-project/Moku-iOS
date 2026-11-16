import SwiftUI

/// Manga reader settings as native Form sections; hosted by the reader sheet and Settings › Reader.
struct ReaderSettingsView: View {
    @Bindable var preferences: ReaderPreferences
    var mediaID: String?
    var landscape = false
    @State private var presetName = ""
    @State private var editingPreset: UUID?
    @State private var naming = false

    private static let modes: [(String, String, String)] = [
        ("single", "Single Page", "rectangle.portrait"),
        ("double", "Two Pages", "book.pages"),
        ("auto", "Automatic", "rectangle.split.2x1"),
        ("longstrip", "Long Strip", "rectangle.grid.1x2"),
    ]
    private static let directions: [(String, String, String)] = [
        ("ltr", "Left to Right", "arrow.right"),
        ("rtl", "Right to Left", "arrow.left"),
    ]

    private var settings: MangaReadingSettings { preferences.settings(for: mediaID) }
    private var isStrip: Bool { settings.pageStyle == "longstrip" }
    private func setting<T>(_ key: WritableKeyPath<MangaReadingSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: key] },
            set: {
                var value = settings
                value[keyPath: key] = $0
                preferences.set(value, for: mediaID)
            })
    }
    private func behaviour<T>(_ key: WritableKeyPath<ReaderBehaviour, T>) -> Binding<T> {
        Binding(
            get: { preferences.document.behaviour[keyPath: key] },
            set: { preferences.document.behaviour[keyPath: key] = $0 })
    }

    var body: some View {
        Group {
            Section("Reading Mode") {
                ForEach(Self.modes, id: \.0) { checkRow($0, binding: setting(\.pageStyle)) }
            }
            if !isStrip {
                Section("Direction") {
                    ForEach(Self.directions, id: \.0) {
                        checkRow($0, binding: setting(\.readingDirection))
                    }
                }
            }
            layout
            Section("Display") {
                Toggle(isOn: setting(\.optimizeContrast)) {
                    Label("Optimize Contrast", systemImage: "circle.lefthalf.filled")
                }
                Toggle(isOn: behaviour(\.pinchZoom)) {
                    Label("Pinch to Zoom", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
            behaviourSection
            if let mediaID {
                Section {
                    Toggle(
                        "Only for This Series",
                        isOn: Binding(
                            get: { preferences.document.overrides[mediaID] != nil },
                            set: { _ in preferences.toggleOverride(mediaID) }))
                } footer: {
                    Text(
                        "Keep this series’ mode, direction, fit and zoom apart from your defaults.")
                }
            }
            presets
        }
        .tint(NavigationStyle.accent)
        .alert(editingPreset == nil ? "Save Preset" : "Rename Preset", isPresented: $naming) {
            TextField("Preset name", text: $presetName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = editingPreset,
                    let index = preferences.document.presets.firstIndex(where: { $0.id == id })
                {
                    preferences.document.presets[index].name = name
                } else {
                    preferences.savePreset(name, mediaID: mediaID)
                }
            }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var layout: some View {
        Section("Layout") {
            Picker(selection: setting(\.fitMode)) {
                Text("Fit Width").tag("width")
                Text("Fit Height").tag("height")
                Text("Fit Screen").tag("screen")
                Text("Original Size").tag("original")
            } label: {
                Label("Page Fit", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            }
            if !isStrip {
                Picker(selection: setting(\.transition)) {
                    Text("None").tag("none")
                    Text("Fade").tag("fade")
                    Text("Slide").tag("slide")
                    Text("Page Turn").tag("flip")
                } label: {
                    Label("Transition", systemImage: "rectangle.stack")
                }
            }
            if settings.pageStyle == "double" || settings.pageStyle == "auto" && landscape {
                Toggle(isOn: setting(\.offsetDoubleSpreads)) {
                    Label("Offset spreads", systemImage: "book")
                }
            }
            if isStrip {
                Toggle(isOn: setting(\.pageGap)) {
                    Label("Gap Between Pages", systemImage: "square.split.1x2")
                }
            }
            Stepper(value: setting(\.readerZoom), in: 0.1...1, step: 0.05) {
                LabeledContent {
                    Text(settings.readerZoom, format: .percent.precision(.fractionLength(0)))
                } label: {
                    Label("Zoom", systemImage: "plus.magnifyingglass")
                }
            }
            .accessibilityValue(
                Text(settings.readerZoom, format: .percent.precision(.fractionLength(0))))
        }
    }

    private var behaviourSection: some View {
        Section("Behavior") {
            if isStrip {
                Toggle(isOn: behaviour(\.autoScroll)) {
                    Label("Auto Scroll", systemImage: "arrow.down.circle")
                }
                if preferences.document.behaviour.autoScroll {
                    Stepper(value: behaviour(\.autoScrollSpeed), in: 1...30, step: 1) {
                        LabeledContent(
                            "Scroll Speed",
                            value: "\(Int(preferences.document.behaviour.autoScrollSpeed))")
                    }
                }
                Toggle("Double-Tap to Show Controls", isOn: behaviour(\.tapToToggleBar))
            } else {
                Toggle(isOn: behaviour(\.tapToTurn)) {
                    Label("Tap Edges to Turn Pages", systemImage: "hand.tap")
                }
                .accessibilityIdentifier("reader.tapToTurn")
            }
            Toggle("Mark Read at Last Page", isOn: behaviour(\.autoMarkRead))
            Toggle("Mark Read When Skipping Ahead", isOn: behaviour(\.markReadOnNext))
            Toggle("Continue to Next Chapter", isOn: behaviour(\.autoNextChapter))
            Toggle("Remember Last Page", isOn: behaviour(\.autoBookmark))
            Stepper(value: behaviour(\.preloadPages), in: 0...10) {
                LabeledContent(
                    "Preload Pages", value: "\(preferences.document.behaviour.preloadPages)")
            }
        }
    }

    private var presets: some View {
        Section {
            ForEach(preferences.document.presets) { preset in
                Button {
                    preferences.set(preset.settings, for: mediaID)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name).foregroundStyle(.primary)
                        Text(summary(preset.settings)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint("Applies this preset")
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        preferences.document.presets.removeAll { $0.id == preset.id }
                    }
                    Button("Rename") { rename(preset) }
                }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") { rename(preset) }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        preferences.document.presets.removeAll { $0.id == preset.id }
                    }
                }
            }
            Button {
                editingPreset = nil
                presetName = ""
                naming = true
            } label: {
                Label("Save Current Settings…", systemImage: "plus")
            }
            .accessibilityIdentifier("reader.savePreset")
        } header: {
            Text("Presets")
        } footer: {
            if !preferences.document.presets.isEmpty { Text("Tap a preset to apply it.") }
        }
    }

    private func checkRow(_ option: (String, String, String), binding: Binding<String>) -> some View
    {
        let selected = binding.wrappedValue == option.0
        return Button {
            binding.wrappedValue = option.0
        } label: {
            HStack {
                Label(option.1, systemImage: option.2)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.body.weight(.semibold))
                        .foregroundStyle(NavigationStyle.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("reader.option.\(option.0)")
    }

    private func rename(_ preset: MangaReaderPreset) {
        editingPreset = preset.id
        presetName = preset.name
        naming = true
    }

    private func summary(_ value: MangaReadingSettings) -> String {
        let mode = Self.modes.first { $0.0 == value.pageStyle }?.1 ?? value.pageStyle
        let direction = value.readingDirection == "rtl" ? "Right to Left" : "Left to Right"
        return value.pageStyle == "longstrip" ? mode : "\(mode) · \(direction)"
    }
}

import SwiftUI

struct ReaderSettingsView: View {
    @Bindable var preferences: ReaderPreferences
    var mediaID: String?
    var landscape = false
    var settingsPage = false
    @State private var presetName = ""
    @State private var editingPreset: UUID?
    @State private var naming = false

    private var settings: MangaReadingSettings { preferences.settings(for: mediaID) }
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
            if settingsPage { pageContent } else { inlineContent }
        }
        .font(.system(size: 14)).buttonStyle(.plain).tint(NavigationStyle.accent)
        .alert(editingPreset == nil ? "Save preset" : "Rename preset", isPresented: $naming) {
            TextField("Preset name", text: $presetName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let id = editingPreset,
                    let index = preferences.document.presets.firstIndex(where: { $0.id == id })
                {
                    preferences.document.presets[index].name = presetName.trimmingCharacters(
                        in: .whitespacesAndNewlines)
                } else {
                    preferences.savePreset(presetName, mediaID: mediaID)
                }
            }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    private var inlineContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            group("Layout") {
                tiles(
                    setting(\.pageStyle),
                    options: [
                        ("single", "Single", "Square"), ("double", "Double", "BookOpen"),
                        ("auto", "Auto", "Sparkle"), ("longstrip", "Strip", "Rows"),
                    ])
                if settings.pageStyle == "double" || settings.pageStyle == "auto" && landscape {
                    toggle("Offset spreads", setting(\.offsetDoubleSpreads))
                }
                if settings.pageStyle == "longstrip" {
                    toggle("Page gap", setting(\.pageGap))
                    toggle("Auto next chapter", behaviour(\.autoNextChapter))
                    toggle("Auto scroll", behaviour(\.autoScroll))
                    if preferences.document.behaviour.autoScroll {
                        HStack {
                            Text("Scroll speed")
                            ReaderSlider(value: behaviour(\.autoScrollSpeed), in: 1...30, step: 1)
                                .accessibilityLabel("Scroll speed")
                            Text("\(Int(preferences.document.behaviour.autoScrollSpeed))")
                                .monospaced()
                        }.frame(minHeight: 44)
                    }
                }
            }
            group("Transition") {
                tiles(
                    setting(\.transition),
                    options: [
                        ("none", "None", "Prohibit"), ("fade", "Fade", "MonitorPlay"),
                        ("slide", "Slide", "ArrowsHorizontal"), ("flip", "Turn", "ArrowsLeftRight"),
                    ])
            }
            group("Fit") {
                tiles(
                    setting(\.fitMode),
                    options: [
                        ("width", "Width", "ArrowsLeftRight"),
                        ("height", "Height", "ArrowsVertical"),
                        ("screen", "Screen", "ArrowsIn"), ("original", "1:1", "ArrowsOut"),
                    ])
            }
            group("Direction") {
                HStack(spacing: 4) {
                    choice(
                        "Left to right", value: "ltr", binding: setting(\.readingDirection),
                        icon: "ArrowsHorizontal")
                    choice(
                        "Right to left", value: "rtl", binding: setting(\.readingDirection),
                        icon: "ArrowsHorizontal")
                }
            }
            group("Zoom") {
                HStack {
                    iconButton("Minus", label: "Zoom out") {
                        setting(\.readerZoom).wrappedValue = max(0.1, settings.readerZoom - 0.1)
                    }
                    ReaderSlider(value: setting(\.readerZoom), in: 0.1...1, step: 0.05)
                        .accessibilityLabel("Zoom")
                    iconButton("Plus", label: "Zoom in") {
                        setting(\.readerZoom).wrappedValue = min(1, settings.readerZoom + 0.1)
                    }
                }
                HStack {
                    Text("\(Int((settings.readerZoom * 100).rounded()))%").monospaced()
                    Spacer()
                    Button("Reset") { setting(\.readerZoom).wrappedValue = 1 }.frame(minHeight: 44)
                }
            }
            group("Image") {
                toggle("Optimize contrast", setting(\.optimizeContrast))
                toggle("Pinch to zoom", behaviour(\.pinchZoom))
                toggle("Mark read on advance", behaviour(\.markReadOnNext))
            }
            if let mediaID {
                Divider()
                toggle(
                    "Per-manga settings",
                    Binding(
                        get: { preferences.document.overrides[mediaID] != nil },
                        set: { _ in preferences.toggleOverride(mediaID) }))
                Text("Layout, fit, direction, zoom and image settings can be saved for this manga.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            group("Presets") {
                Button("+ Save current") {
                    editingPreset = nil
                    presetName = ""
                    naming = true
                }
                .frame(minHeight: 44).accessibilityIdentifier("reader.savePreset")
                ForEach(preferences.document.presets) { preset in
                    HStack {
                        Button {
                            preferences.set(preset.settings, for: mediaID)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name)
                                Text(
                                    "\(preset.settings.pageStyle) · \(preset.settings.fitMode) · \(preset.settings.readingDirection.uppercased())"
                                )
                                .font(.system(.caption2, design: .monospaced)).foregroundStyle(
                                    .secondary)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        iconButton("PencilSimple", label: "Rename \(preset.name)") {
                            editingPreset = preset.id
                            presetName = preset.name
                            naming = true
                        }
                        iconButton("Trash", label: "Delete \(preset.name)") {
                            preferences.document.presets.removeAll { $0.id == preset.id }
                        }
                    }
                }
                if preferences.document.presets.isEmpty {
                    Text("No presets yet — save the current settings to make one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            ReaderDisclosure("Behaviour") {
                VStack(spacing: 8) {
                    toggle("Auto-mark read", behaviour(\.autoMarkRead))
                    toggle("Auto-advance chapters", behaviour(\.autoNextChapter))
                    toggle("Auto-bookmark", behaviour(\.autoBookmark))
                    Stepper(
                        "Pages to preload: \(preferences.document.behaviour.preloadPages)",
                        value: behaviour(\.preloadPages), in: 0...10
                    ).frame(minHeight: 44)
                }.padding(.top, 12)
            }
            ReaderDisclosure("Bars & Chrome") {
                VStack(spacing: 8) {
                    HStack {
                        ForEach(["top", "left", "right"], id: \.self) { position in
                            choice(
                                position.capitalized, value: position,
                                binding: setting(\.barPosition))
                        }
                    }
                    toggle("Tap to toggle bar", behaviour(\.tapToToggleBar))
                    toggle("Containerized view", behaviour(\.containerized))
                    Text("Double-tap the center to show or hide controls.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 12)
            }
        }
    }
    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            GeneralSection("Layout") {
                pagePicker(
                    "Page layout", setting(\.pageStyle),
                    [
                        ("single", "Single"), ("double", "Double"), ("auto", "Auto"),
                        ("longstrip", "Strip"),
                    ])
                GeneralStyle.divider
                pagePicker(
                    "Transition", setting(\.transition),
                    [("none", "None"), ("fade", "Fade"), ("slide", "Slide"), ("flip", "Turn")])
                GeneralStyle.divider
                pagePicker(
                    "Fit", setting(\.fitMode),
                    [
                        ("width", "Width"), ("height", "Height"), ("screen", "Screen"),
                        ("original", "Original"),
                    ])
                GeneralStyle.divider
                pagePicker(
                    "Reading direction", setting(\.readingDirection),
                    [("ltr", "Left to right"), ("rtl", "Right to left")])
                if settings.pageStyle == "double" || settings.pageStyle == "auto" {
                    GeneralStyle.divider
                    pageToggle("Offset spreads", setting(\.offsetDoubleSpreads))
                }
                if settings.pageStyle == "longstrip" {
                    GeneralStyle.divider
                    pageToggle("Page gap", setting(\.pageGap))
                    GeneralStyle.divider
                    pageToggle("Auto scroll", behaviour(\.autoScroll))
                    if preferences.document.behaviour.autoScroll {
                        GeneralStyle.divider
                        GeneralRow("Scroll speed", detail: "") {
                            Stepper(value: behaviour(\.autoScrollSpeed), in: 1...30, step: 1) {
                                Text("\(Int(preferences.document.behaviour.autoScrollSpeed))")
                            }.frame(width: 150).font(.system(size: 14)).accessibilityLabel(
                                "Scroll speed")
                        }
                    }
                }
            }
            GeneralSection("Image") {
                GeneralRow("Zoom", detail: "Default page scale.") {
                    HStack(spacing: 8) {
                        iconButton("Minus", label: "Zoom out") {
                            setting(\.readerZoom).wrappedValue = max(
                                0.1, settings.readerZoom - 0.05)
                        }
                        Text("\(Int((settings.readerZoom * 100).rounded()))%").font(
                            .system(size: 14)
                        )
                        .monospacedDigit()
                        iconButton("Plus", label: "Zoom in") {
                            setting(\.readerZoom).wrappedValue = min(1, settings.readerZoom + 0.05)
                        }
                    }.foregroundStyle(GeneralStyle.text)
                }
                GeneralStyle.divider
                pageToggle("Optimize contrast", setting(\.optimizeContrast))
                GeneralStyle.divider
                pageToggle("Pinch to zoom", behaviour(\.pinchZoom))
            }
            GeneralSection("Behaviour") {
                pageToggle("Auto-mark read", behaviour(\.autoMarkRead))
                GeneralStyle.divider
                pageToggle("Mark read on advance", behaviour(\.markReadOnNext))
                GeneralStyle.divider
                pageToggle("Auto-advance chapters", behaviour(\.autoNextChapter))
                GeneralStyle.divider
                pageToggle("Auto-bookmark", behaviour(\.autoBookmark))
                GeneralStyle.divider
                GeneralRow("Pages to preload", detail: "") {
                    ChoicePicker(
                        title: "", selection: behaviour(\.preloadPages),
                        options: (0...10).map { ($0, String($0)) }
                    )
                    .font(.system(size: 14)).accessibilityLabel("Pages to preload")
                }
            }
            GeneralSection("Controls") {
                pagePicker(
                    "Bar position", setting(\.barPosition),
                    [("top", "Top"), ("left", "Left"), ("right", "Right")])
                GeneralStyle.divider
                pageToggle("Tap to toggle bar", behaviour(\.tapToToggleBar))
                GeneralStyle.divider
                pageToggle("Containerized view", behaviour(\.containerized))
            }
            GeneralSection("Presets") {
                GeneralRow("Current settings", detail: "") {
                    Button("Save") {
                        editingPreset = nil
                        presetName = ""
                        naming = true
                    }
                    .buttonStyle(GeneralTextButtonStyle()).accessibilityIdentifier(
                        "reader.savePreset")
                }
                ForEach(preferences.document.presets) { preset in
                    GeneralStyle.divider
                    GeneralRow(preset.name, detail: "") {
                        OverflowMenu {
                            Button("Apply") { preferences.set(preset.settings, for: mediaID) }
                            Button("Rename") {
                                editingPreset = preset.id
                                presetName = preset.name
                                naming = true
                            }
                            Button("Delete", role: .destructive) {
                                preferences.document.presets.removeAll { $0.id == preset.id }
                            }
                        } label: {
                            Text("Manage").font(.system(size: 14)).foregroundStyle(
                                GeneralStyle.text
                            ).frame(
                                minHeight: 44)
                        }.accessibilityLabel("Manage \(preset.name)")
                    }
                }
            }
        }
    }
    private func pagePicker(
        _ title: String, _ selection: Binding<String>, _ options: [(String, String)]
    ) -> some View {
        GeneralRow(title, detail: "") {
            ChoicePicker(title: "", selection: selection, options: options)
                .font(.system(size: 14)).accessibilityLabel(title)
        }
    }
    private func pageToggle(_ title: String, _ selection: Binding<Bool>) -> some View {
        GeneralRow(title, detail: "") {
            Toggle(title, isOn: selection).toggleStyle(GeneralToggleStyle())
        }
    }
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
        -> some View
    {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(.caption, design: .monospaced))
                .tracking(1).foregroundStyle(.secondary)
            content()
        }
    }
    private func toggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding).frame(minHeight: 44)
    }
    private func tiles(_ binding: Binding<String>, options: [(String, String, String)]) -> some View
    {
        HStack(spacing: 5) {
            ForEach(options, id: \.0) { value, label, icon in
                choice(label, value: value, binding: binding, icon: icon, tile: true)
            }
        }
    }
    private func choice(
        _ title: String, value: String, binding: Binding<String>,
        icon: String? = nil, tile: Bool = false
    ) -> some View {
        let selected = binding.wrappedValue == value
        return Button {
            binding.wrappedValue = value
        } label: {
            (tile ? AnyLayout(VStackLayout(spacing: 7)) : AnyLayout(HStackLayout(spacing: 5))) {
                if let icon {
                    PhosphorIcon(icon, size: 20, weight: tile && selected ? "fill" : "light")
                }
                Text(title).font(.system(size: 11, design: .monospaced)).fixedSize(
                    horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: tile ? 62 : 44)
            .foregroundStyle(selected ? NavigationStyle.accent : .secondary)
            .background(
                selected ? NavigationStyle.accent.opacity(0.18) : .clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5).stroke(
                    selected ? NavigationStyle.accent.opacity(0.4) : .white.opacity(0.15))
            }
        }.accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(
            "reader.option.\(value)")
    }
    private func iconButton(_ name: String, label: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) { PhosphorIcon(name, weight: "light").frame(width: 44, height: 44) }
            .accessibilityLabel(label)
    }
}

private struct ReaderDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                    Spacer()
                    PhosphorIcon("CaretRight", size: 14).rotationEffect(.degrees(expanded ? 90 : 0))
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded { content() }
        }
    }
}

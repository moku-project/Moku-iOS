import SwiftUI
import UIKit

struct NativeTheme: Codable, Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var name: String
    var background = "#080808"
    var surface = "#171717"
    var accent = "#7aaa7a"
    var text = "#e8e6e0"
    var secondary = "#b9bcc0"
    var muted = "#9b9b9b"
    var border = "#252525"
    var isLight = false
    // Same tokens as desktop themes.css and Android MokuThemes.kt.
    static let builtins: [NativeTheme] = [
        .init(id: "dark", name: "Dark", background: "#080808", surface: "#111111", accent: "#7aaa7a", text: "#ffffff", secondary: "#e8e6e0", muted: "#b0aea8", border: "#252525"),
        .init(id: "light", name: "Light", background: "#e2deda", surface: "#f5f2ec", accent: "#3f9142", text: "#080806", secondary: "#181612", muted: "#38342e", border: "#c4c0b8", isLight: true),
        .init(id: "midnight", name: "Midnight", background: "#080c18", surface: "#101428", accent: "#6a7ab8", text: "#eeeef8", secondary: "#c0c4d8", muted: "#808498", border: "#1a2035"),
        .init(id: "original", name: "Original", background: "#0c0c0c", surface: "#151515", accent: "#6b8f6b", text: "#f0efec", secondary: "#c8c6c0", muted: "#8a8880", border: "#1c1c1c"),
        .init(id: "warm", name: "Warm", background: "#100e08", surface: "#1c1810", accent: "#c0902a", text: "#f5f0e0", secondary: "#d8d0b0", muted: "#988c60", border: "#201c10"),
    ]
    static func custom(_ data: Data) -> [NativeTheme] { (try? JSONDecoder().decode([NativeTheme].self, from: data)) ?? [] }
    static func resolve(_ id: String, custom: Data) -> NativeTheme {
        if let builtin = builtins.first(where: { $0.id == id }) { return builtin }
        return Self.custom(custom).first { $0.id == id } ?? builtins[0]
    }
}
extension Color {
    init(themeHex: String) {
        let value = UInt32(themeHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    @MainActor var themeHex: String {
        var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
struct AppearanceSettingsContent: View {
    @AppStorage("preferences.theme") private var theme = "dark"
    @AppStorage("preferences.systemTheme") private var system = false
    @AppStorage("preferences.darkTheme") private var darkTheme = "dark"
    @AppStorage("preferences.lightTheme") private var lightTheme = "light"
    @AppStorage("preferences.customThemes") private var custom = Data()
    @AppStorage("preferences.solidSurfaces") private var solid = false
    @AppStorage("preferences.cropCovers") private var cropCovers = true
    @State private var draft: NativeTheme?
    var options: [(String, String)] { (NativeTheme.builtins + NativeTheme.custom(custom)).map { ($0.id, $0.name) } }
    var body: some View {
        SettingsForm {
            Section {
                SettingsToggle("Match system theme", detail: "Follow the device’s light and dark appearance.", isOn: $system)
                if system {
                    choice("Dark theme", value: $darkTheme)
                    choice("Light theme", value: $lightTheme)
                } else {
                    choice("App theme", value: $theme)
                }
                ThemeSwatches(selected: system ? nil : theme, themes: NativeTheme.builtins + NativeTheme.custom(custom)) { id in
                    theme = id
                    system = false
                }
            } header: {
                Text("Theme")
            }
            Section {
                ForEach(NativeTheme.custom(custom)) { item in
                    Menu {
                        Button("Apply", systemImage: "checkmark.circle") { theme = item.id; system = false }
                        Button("Edit", systemImage: "pencil") { draft = item }
                        Button("Copy as JSON", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = item.desktopJSON
                            Toaster.shared.show("Theme copied", detail: "Paste it into Moku desktop’s theme editor or another device.")
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                    } label: {
                        HStack {
                            Circle().fill(Color(themeHex: item.accent)).frame(width: 14, height: 14)
                            Text(item.name)
                            Spacer(minLength: 8)
                            if theme == item.id && !system {
                                Image(systemName: "checkmark").foregroundStyle(NavigationStyle.accent)
                            }
                            Image(systemName: "ellipsis.circle").foregroundStyle(NavigationStyle.accent)
                        }
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Manage \(item.name)")
                    .swipeActions {
                        Button("Delete", role: .destructive) { delete(item) }
                        Button("Edit") { draft = item }
                    }
                }
                Button {
                    guard let text = UIPasteboard.general.string, let imported = NativeTheme(desktopJSON: text) else {
                        Toaster.shared.show("No theme on the clipboard", detail: "Copy a theme’s JSON first.", kind: .error)
                        return
                    }
                    saveThemes(NativeTheme.custom(custom) + [imported])
                    Toaster.shared.show("Imported \(imported.name)")
                } label: {
                    Label("Import theme from clipboard", systemImage: "doc.on.clipboard")
                }
                Button {
                    var value = NativeTheme.resolve(theme, custom: custom)
                    value.id = UUID().uuidString; value.name = ""
                    draft = value
                } label: {
                    Label("Create custom palette", systemImage: "paintpalette")
                }
            } header: {
                Text("Custom themes")
            } footer: {
                Text("Import a theme copied from Moku desktop or another device, or create one from the current colors.")
            }
            Section("Interface") {
                SettingsToggle("Solid interface", detail: "Use opaque navigation, reader, and player controls.", isOn: $solid)
            }
            Section {
                NavigationLink {
                    ContentTypesSettingsView()
                } label: {
                    Label("Content Types", systemImage: "square.stack")
                }
                .accessibilityIdentifier("settings.appearance.contentTypes")
            } footer: {
                Text("Choose which types the content button offers, and in what order.")
            }
            Section("Covers") {
                SettingsToggle("Crop cover images", detail: "Fill the cover frame.", isOn: $cropCovers)
            }
        }
        .sheet(item: $draft) { value in
            ThemeEditor(initial: value) { next in
                var values = NativeTheme.custom(custom).filter { $0.id != next.id }
                values.append(next); saveThemes(values); draft = nil
            }
        }
    }
    private func delete(_ item: NativeTheme) {
        saveThemes(NativeTheme.custom(custom).filter { $0.id != item.id })
        if theme == item.id { theme = "dark" }
        if darkTheme == item.id { darkTheme = "dark" }
        if lightTheme == item.id { lightTheme = "light" }
    }
    private func saveThemes(_ value: [NativeTheme]) { if let data = try? JSONEncoder().encode(value) { custom = data } }
    private func choice(_ title: String, value: Binding<String>) -> some View {
        SettingsPicker(title, selection: value, options: options)
            .accessibilityValue(value.wrappedValue)
    }
}

/// A row of theme previews; tapping one applies it.
private struct ThemeSwatches: View {
    let selected: String?
    let themes: [NativeTheme]
    let select: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(themes) { item in
                    Button { select(item.id) } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(themeHex: item.background))
                                .overlay(alignment: .bottomLeading) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Capsule().fill(Color(themeHex: item.text)).frame(width: 28, height: 4)
                                        Capsule().fill(Color(themeHex: item.muted)).frame(width: 20, height: 4)
                                        Capsule().fill(Color(themeHex: item.accent)).frame(width: 16, height: 6)
                                    }
                                    .padding(8)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(
                                            selected == item.id ? NavigationStyle.accent : Color(themeHex: item.border),
                                            lineWidth: selected == item.id ? 2.5 : 1)
                                }
                                .frame(width: 64, height: 64)
                            Text(item.name).font(.caption)
                                .foregroundStyle(selected == item.id ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                .lineLimit(1)
                        }
                        .frame(width: 72)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.name)
                    .accessibilityAddTraits(selected == item.id ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }
}
private struct ThemeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var value: NativeTheme
    let save: (NativeTheme) -> Void
    init(initial: NativeTheme, save: @escaping (NativeTheme) -> Void) { _value = State(initialValue: initial); self.save = save }
    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    TextField("Name", text: $value.name)
                    SettingsToggle("Light appearance", detail: "Use dark text in system controls.", isOn: $value.isLight)
                }
                Section("Colors") {
                    color("Background", \.background)
                    color("Surface", \.surface)
                    color("Accent", \.accent)
                    color("Text", \.text)
                    color("Secondary text", \.secondary)
                    color("Muted text", \.muted)
                    color("Dividers", \.border)
                }
            }
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle(value.name.isEmpty ? "New theme" : value.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines); save(value) }
                        .disabled(value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    private func color(_ title: String, _ key: WritableKeyPath<NativeTheme, String>) -> some View {
        ColorPicker(title, selection: Binding(get: { Color(themeHex: value[keyPath: key]) }, set: { value[keyPath: key] = $0.themeHex }), supportsOpacity: false)
    }
}

/// Desktop ThemeEditor's JSON (`{ id, name, tokens }`), so themes move between apps.
extension NativeTheme {
    var desktopJSON: String {
        let tokens = [
            "bg-void": background, "bg-base": background, "bg-surface": surface, "bg-raised": surface,
            "border-base": border, "text-primary": text, "text-secondary": secondary,
            "text-muted": muted, "accent": accent, "accent-fg": accent,
        ]
        let object: [String: Any] = ["id": "custom:\(id)", "name": name, "tokens": tokens]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    init?(desktopJSON text: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            let tokens = object["tokens"] as? [String: String]
        else { return nil }
        func hex(_ keys: String...) -> String? {
            keys.lazy.compactMap { tokens[$0] }.first { $0.hasPrefix("#") && ($0.count == 7) }
        }
        guard let background = hex("bg-void", "bg-base"), let text = hex("text-primary") else { return nil }
        self.init(name: (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Imported theme")
        self.background = background
        self.text = text
        surface = hex("bg-raised", "bg-surface") ?? surface
        accent = hex("accent-fg", "accent") ?? accent
        secondary = hex("text-secondary") ?? secondary
        muted = hex("text-muted") ?? muted
        border = hex("border-base", "border-strong") ?? border
        let value = UInt32(background.dropFirst(), radix: 16) ?? 0
        let luminance = 0.2126 * Double(value >> 16 & 255) + 0.7152 * Double(value >> 8 & 255) + 0.0722 * Double(value & 255)
        isLight = luminance > 140
    }
}

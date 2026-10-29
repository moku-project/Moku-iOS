import SwiftUI

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
    static let builtins: [NativeTheme] = [
        .init(id: "midnight", name: "Midnight"),
        .init(id: "original", name: "Original", background: "#101010", surface: "#151515", accent: "#a8c4a8", text: "#f0efec"),
        .init(id: "dark", name: "Dark", background: "#080808", surface: "#111111", accent: "#bcd8bc", text: "#ffffff"),
        .init(id: "light", name: "Light", background: "#f4f2ee", surface: "#faf8f4", accent: "#2a5a2a", text: "#1a1916", secondary: "#44433f", muted: "#65645f", border: "#d4d2cd", isLight: true),
        .init(id: "warm", name: "Warm", background: "#16130c", surface: "#1c1810", accent: "#e0b860", text: "#f5f0e0"),
        .init(id: "charcoal", name: "Charcoal", background: "#1a1a1a", surface: "#262626", accent: "#8cb3db"),
        .init(id: "sepia", name: "Sepia", background: "#1a160f", surface: "#262118", accent: "#d1a65c"),
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
    @AppStorage("preferences.theme") private var theme = "midnight"
    @AppStorage("preferences.systemTheme") private var system = false
    @AppStorage("preferences.darkTheme") private var darkTheme = "midnight"
    @AppStorage("preferences.lightTheme") private var lightTheme = "light"
    @AppStorage("preferences.customThemes") private var custom = Data()
    @AppStorage("preferences.solidSurfaces") private var solid = false
    @AppStorage("preferences.cropCovers") private var cropCovers = true
    @State private var draft: NativeTheme?
    var options: [(String, String)] { (NativeTheme.builtins + NativeTheme.custom(custom)).map { ($0.id, $0.name) } }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            GeneralSection("Theme") {
                GeneralRow("Match system theme", detail: "Follow the device’s light and dark appearance.") {
                    Toggle("Match system theme", isOn: $system).toggleStyle(GeneralToggleStyle())
                }
                GeneralStyle.divider
                if system {
                    choice("Dark theme", value: $darkTheme)
                    GeneralStyle.divider
                    choice("Light theme", value: $lightTheme)
                } else { choice("App theme", value: $theme) }
            }
            GeneralSection("Custom themes") {
                ForEach(NativeTheme.custom(custom)) { item in
                    GeneralRow(item.name, detail: "") {
                        OverflowMenu {
                            Button("Apply") { theme = item.id; system = false }
                            Button("Edit") { draft = item }
                            Button("Delete", role: .destructive) {
                                saveThemes(NativeTheme.custom(custom).filter { $0.id != item.id })
                                if theme == item.id { theme = "midnight" }
                                if darkTheme == item.id { darkTheme = "midnight" }
                                if lightTheme == item.id { lightTheme = "light" }
                            }
                        } label: { Text("Manage").font(.system(size: 14)).frame(minHeight: 44).foregroundStyle(GeneralStyle.text) }
                    }
                    GeneralStyle.divider
                }
                GeneralRow("Custom palette", detail: "Create a theme from the current colors.") {
                    Button("Create") {
                        var value = NativeTheme.resolve(theme, custom: custom)
                        value.id = UUID().uuidString; value.name = ""
                        draft = value
                    }.buttonStyle(GeneralTextButtonStyle())
                }
            }
            GeneralSection("Interface") {
                GeneralRow("Solid interface", detail: "Use opaque navigation, reader, and player controls.") { Toggle("Solid interface", isOn: $solid).toggleStyle(GeneralToggleStyle()) }
            }
            GeneralSection("Covers") {
                GeneralRow("Crop cover images", detail: "Fill the cover frame.") { Toggle("Crop cover images", isOn: $cropCovers).toggleStyle(GeneralToggleStyle()) }
            }
        }.sheet(item: $draft) { value in
            ThemeEditor(initial: value) { next in
                var values = NativeTheme.custom(custom).filter { $0.id != next.id }
                values.append(next); saveThemes(values); draft = nil
            }
        }
    }
    private func saveThemes(_ value: [NativeTheme]) { if let data = try? JSONEncoder().encode(value) { custom = data } }
    private func choice(_ title: String, value: Binding<String>) -> some View {
        GeneralRow(title, detail: "") {
            ChoicePicker(title: "", selection: value, options: options).font(.system(size: 14))
                .accessibilityIdentifier("settings.picker.\(title)").accessibilityValue(value.wrappedValue)
        }
    }
}
private struct ThemeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var value: NativeTheme
    let save: (NativeTheme) -> Void
    init(initial: NativeTheme, save: @escaping (NativeTheme) -> Void) { _value = State(initialValue: initial); self.save = save }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GeneralSection("Theme") {
                    GeneralRow("Name", detail: "") { TextField("Name", text: $value.name).generalInput().frame(width: 150) }
                    GeneralRow("Light appearance", detail: "Use dark text in system controls.") { Toggle("Light appearance", isOn: $value.isLight).toggleStyle(GeneralToggleStyle()) }
                }
                GeneralSection("Colors") {
                    color("Background", \.background)
                    color("Surface", \.surface)
                    color("Accent", \.accent)
                    color("Text", \.text)
                    color("Secondary text", \.secondary)
                    color("Muted text", \.muted)
                    color("Dividers", \.border)
                }
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button("Save") { value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines); save(value) }
                        .disabled(value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.buttonStyle(GeneralTextButtonStyle())
            }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(NavigationStyle.background)
    }
    private func color(_ title: String, _ key: WritableKeyPath<NativeTheme, String>) -> some View {
        GeneralRow(title, detail: "") {
            ColorPicker(title, selection: Binding(get: { Color(themeHex: value[keyPath: key]) }, set: { value[keyPath: key] = $0.themeHex }), supportsOpacity: false).labelsHidden()
        }
    }
}

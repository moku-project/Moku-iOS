import SwiftUI

struct ReaderShortcut: Identifiable, Sendable {
    let id: String
    let title: String
    let defaultValue: String
    static let all: [ReaderShortcut] = [
        .init(id: "pageRight", title: "Turn page right", defaultValue: "ArrowRight"),
        .init(id: "pageLeft", title: "Turn page left", defaultValue: "ArrowLeft"),
        .init(id: "firstPage", title: "First page", defaultValue: "ctrl+ArrowLeft"),
        .init(id: "lastPage", title: "Last page", defaultValue: "ctrl+ArrowRight"),
        .init(id: "chapterRight", title: "Next chapter", defaultValue: "]"),
        .init(id: "chapterLeft", title: "Previous chapter", defaultValue: "["),
        .init(id: "exit", title: "Exit reader", defaultValue: "Backspace"),
        .init(id: "direction", title: "Toggle reading direction", defaultValue: "d"),
        .init(id: "layout", title: "Cycle page layout", defaultValue: "q"),
        .init(id: "fullscreen", title: "Toggle full-screen controls", defaultValue: "f"),
        .init(id: "settings", title: "Reader settings", defaultValue: "o"),
        .init(id: "scroll", title: "Toggle auto scroll", defaultValue: "s"),
    ]
    static func values(_ data: Data) -> [String: String] {
        let saved = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        return Dictionary(
            uniqueKeysWithValues: all.map { ($0.id, saved[$0.id] ?? $0.defaultValue) })
    }
    static func normalized(_ value: String) -> String {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(
            separator: "+", omittingEmptySubsequences: false
        ).map(String.init)
        guard let key = parts.last else { return "" }
        return (parts.dropLast().sorted() + [key]).joined(separator: "+")
    }
    static func valid(_ value: String) -> Bool {
        if value.isEmpty { return true }
        let parts = normalized(value).split(separator: "+", omittingEmptySubsequences: false).map(
            String.init)
        guard let key = parts.last,
            key.count == 1
                || [
                    "arrowleft", "arrowright", "arrowup", "arrowdown", "backspace", "escape",
                    "space", "return", "tab",
                ].contains(key)
        else { return false }
        let modifiers = parts.dropLast()
        return Set(modifiers).count == modifiers.count
            && modifiers.allSatisfy { ["ctrl", "cmd", "alt", "shift"].contains($0) }
    }
    static func matches(_ value: String, press: KeyPress) -> Bool {
        guard !value.isEmpty, valid(value) else { return false }
        let parts = normalized(value).split(separator: "+").map(String.init)
        var modifiers: EventModifiers = []
        if parts.contains("ctrl") { modifiers.insert(.control) }
        if parts.contains("cmd") { modifiers.insert(.command) }
        if parts.contains("alt") { modifiers.insert(.option) }
        if parts.contains("shift") { modifiers.insert(.shift) }
        guard press.modifiers.intersection([.control, .command, .option, .shift]) == modifiers
        else { return false }
        switch parts.last {
        case "arrowleft": return press.key == .leftArrow
        case "arrowright": return press.key == .rightArrow
        case "arrowup": return press.key == .upArrow
        case "arrowdown": return press.key == .downArrow
        case "backspace": return press.key == .delete
        case "escape": return press.key == .escape
        case "space": return press.key == .space
        case "return": return press.key == .return
        case "tab": return press.key == .tab
        default: return press.characters.lowercased() == parts.last
        }
    }
}
struct KeybindsSettingsContent: View {
    @AppStorage("keybinds.reader") private var data = Data()
    @AppStorage("keybinds.player.play") private var play = " "
    @AppStorage("keybinds.player.previous") private var previous = "["
    @AppStorage("keybinds.player.next") private var next = "]"
    @State private var selected: ReaderShortcut?
    @State private var draft = ""
    @State private var notice: String?
    var body: some View {
        SettingsForm {
            Section {
                ForEach(ReaderShortcut.all) { item in
                    Button {
                        draft = ReaderShortcut.values(data)[item.id] ?? item.defaultValue
                        selected = item
                    } label: {
                        LabeledContent(item.title) {
                            Text(ReaderShortcut.values(data)[item.id]?.nonemptyShortcut ?? "None")
                                .font(.body.monospaced())
                        }
                        .foregroundStyle(.primary)
                    }
                }
            } header: {
                Text("Reader")
            } footer: {
                Text("For hardware keyboards. Tap a shortcut to change it.")
            }
            Section("Player") {
                choice(
                    "Play or pause", value: $play,
                    options: [(" ", "Space"), ("k", "K"), ("", "None")])
                choice(
                    "Previous episode", value: $previous,
                    options: [("[", "["), ("p", "P"), ("", "None")])
                choice(
                    "Next episode", value: $next, options: [("]", "]"), ("n", "N"), ("", "None")])
            }
            Section {
                Button("Restore default shortcuts", role: .destructive) {
                    data = Data()
                    play = " "
                    previous = "["
                    next = "]"
                }
            }
            SettingsNotice(text: notice)
        }.alert(
            selected?.title ?? "Shortcut",
            isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })
        ) {
            TextField("Shortcut", text: $draft).textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let selected { save(selected) } }
        } message: {
            Text(
                "Enter a key, optionally with ctrl+, cmd+, alt+, or shift+. Leave blank to disable."
            )
        }
    }
    private func save(_ item: ReaderShortcut) {
        guard ReaderShortcut.valid(draft) else {
            notice = "Enter a valid shortcut."
            return
        }
        var values = ReaderShortcut.values(data)
        guard
            draft.isEmpty
                || !values.contains(where: {
                    $0.key != item.id
                        && ReaderShortcut.normalized($0.value) == ReaderShortcut.normalized(draft)
                })
        else {
            notice = "This shortcut is already assigned."
            return
        }
        values[item.id] = draft
        if let encoded = try? JSONEncoder().encode(values) {
            data = encoded
            notice = nil
        }
    }
    private func choice(_ title: String, value: Binding<String>, options: [(String, String)])
        -> some View
    {
        SettingsPicker(title, selection: value, options: options)
            .accessibilityValue(value.wrappedValue)
    }
}
extension String { fileprivate var nonemptyShortcut: String? { isEmpty ? nil : self } }

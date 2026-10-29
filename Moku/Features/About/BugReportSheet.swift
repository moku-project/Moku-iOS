import SwiftUI
import UIKit

/// Desktop BugReporter: a prefilled GitHub issue (bug or feature request) with
/// the app, iOS and server versions, plus only the settings groups you tick.
/// Secrets, PINs, keybinds, themes, bookmarks and per-title data never leave.
struct BugReportSheet: View {
    @Environment(AppDataStore.self) private var appData
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var feature = false
    @State private var title = ""
    @State private var description = ""
    @State private var steps = ""
    @State private var expected = ""
    @State private var actual = ""
    @State private var groups: Set<String> = []
    @State private var server = "unknown"

    static let settingGroups: [(name: String, prefixes: [String])] = [
        ("Library", ["library.", "contentMode", "chapter."]),
        ("Reader", ["reader.", "novel."]),
        ("Player", ["player."]),
        ("Appearance", ["preferences.theme", "preferences.lightTheme", "preferences.darkTheme", "preferences.systemTheme", "preferences.solidSurfaces", "preferences.interfaceScale", "preferences.cropCovers", "preferences.animations"]),
        ("Downloads", ["downloads.", "preferences.storageLimitGB"]),
        ("Automation", ["automation."]),
        ("Sync", ["sync."]),
        ("Performance", ["preferences.renderLimit", "preferences.idleTimeout"]),
    ]
    /// Never attached, whatever is ticked.
    private static let redacted = ["password", "pin", "token", "secret", "lock", "keybinds.", "customThemes",
                                   "bookmarks", "positions", "reader.preferences", "pairing", "history"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $feature) {
                    Text("Bug").tag(false)
                    Text("Feature request").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                Section("Summary") {
                    TextField(feature ? "What would you like?" : "What went wrong?", text: $title)
                    TextField(feature ? "The problem it solves" : "Describe what happened", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }
                if feature {
                    Section("Idea") {
                        TextField("How it could work", text: $expected, axis: .vertical).lineLimit(2...6)
                    }
                } else {
                    Section("Details") {
                        TextField("Steps to reproduce", text: $steps, axis: .vertical).lineLimit(2...6)
                        TextField("What you expected", text: $expected, axis: .vertical).lineLimit(1...4)
                        TextField("What happened instead", text: $actual, axis: .vertical).lineLimit(1...4)
                    }
                    Section {
                        ForEach(Self.settingGroups, id: \.name) { group in
                            Toggle(group.name, isOn: Binding(
                                get: { groups.contains(group.name) },
                                set: { if $0 { groups.insert(group.name) } else { groups.remove(group.name) } }))
                        }
                    } header: {
                        Text("Attach settings")
                    } footer: {
                        Text("Only the groups you choose are included. Passwords, PINs, keybinds, themes, bookmarks and reading positions are never attached.")
                    }
                }
                Section {
                    Button("Open on GitHub") { if let url = issueURL { openURL(url); dismiss() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Copy as Markdown") {
                        UIPasteboard.general.string = markdown
                        Toaster.shared.show("Report copied")
                    }
                }
            }
            .textCase(nil)
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle("Report an issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await loadServer() }
        }
    }

    private var environment: String {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return "Moku for iOS \(version) · iOS \(UIDevice.current.systemVersion) · \(model) · Tsunagu \(server)"
    }

    private var settingsBlock: String {
        let chosen = Self.settingGroups.filter { groups.contains($0.name) }.flatMap(\.prefixes)
        guard !chosen.isEmpty else { return "" }
        let values = appData.preferences.dictionaryRepresentation()
            .filter { key, _ in
                chosen.contains { key.hasPrefix($0) }
                    && !Self.redacted.contains { key.localizedCaseInsensitiveContains($0) }
            }
            .sorted { $0.key < $1.key }
            .map { key, value -> String in
                let text: String
                switch value {
                case let data as Data: text = String(data: data, encoding: .utf8).map { $0.count > 400 ? "<\(data.count) bytes>" : $0 } ?? "<\(data.count) bytes>"
                case let string as String: text = "\"\(string)\""
                default: text = "\(value)"
                }
                return "\(key): \(text)"
            }
        return values.joined(separator: "\n")
    }

    private var markdown: String {
        var parts: [String] = ["## \(feature ? "[Feature]" : "[Bug]") \(title)"]
        if !description.isEmpty { parts.append("**\(feature ? "Problem" : "What happened")**\n\(description)") }
        if feature {
            if !expected.isEmpty { parts.append("**Proposed solution**\n\(expected)") }
        } else {
            if !steps.isEmpty { parts.append("**Steps to reproduce**\n\(steps)") }
            if !expected.isEmpty { parts.append("**Expected**\n\(expected)") }
            if !actual.isEmpty { parts.append("**Actual**\n\(actual)") }
        }
        parts.append("**Environment**\n\(environment)")
        if !settingsBlock.isEmpty { parts.append("**Settings**\n```yaml\n\(settingsBlock)\n```") }
        return parts.joined(separator: "\n\n")
    }

    private var issueURL: URL? {
        var parts = URLComponents(string: "https://github.com/moku-project/Moku-iOS/issues/new")!
        var body = markdown.components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
        // GitHub rejects very long prefilled URLs; the Markdown copy keeps everything.
        if body.count > 6000 { body = String(body.prefix(6000)) + "\n\n(Settings trimmed; paste the copied report for the full list.)" }
        parts.queryItems = [
            URLQueryItem(name: "title", value: "\(feature ? "[Feature]" : "[Bug]") \(title)"),
            URLQueryItem(name: "labels", value: feature ? "enhancement" : "bug"),
            URLQueryItem(name: "body", value: body),
        ]
        return parts.url
    }

    private func loadServer() async {
        struct Response: Decodable, Sendable { struct About: Decodable, Sendable { let version: String }; let about: About }
        if let response: Response = try? await BackendAPI.shared.graphql("{ about { version } }", requiresSourceRuntime: false) {
            server = response.about.version
        }
    }
}

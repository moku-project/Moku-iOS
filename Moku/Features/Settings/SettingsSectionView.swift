import SwiftUI

struct SettingsSectionView: View {
    let category: SettingsCategory
    @Environment(\.dismiss) private var dismiss

    let openExtensions: () -> Void
    @Environment(HomeStore.self) private var home
    @Environment(ReaderPreferences.self) private var readerPreferences
    @AppStorage("preferences.language") private var language = "all"
    @AppStorage("preferences.interfaceScale") private var interfaceScale = 100.0
    @AppStorage("preferences.idleTimeout") private var idleTimeout = 5
    @AppStorage("preferences.animations") private var animations = true
    @AppStorage("preferences.theme") private var theme = "midnight"
    @AppStorage("preferences.solidSurfaces") private var solidSurfaces = false
    @AppStorage("preferences.cropCovers") private var cropCovers = true
    @AppStorage("library.listLayout") private var listLayout = false
    @AppStorage("library.showAllInSaved") private var showAllInSaved = true
    @AppStorage("library.hideCompletedInSaved") private var hideCompletedInSaved = false
    @AppStorage("library.disableAutoComplete") private var disableAutoComplete = false
    @AppStorage("library.defaultTab") private var defaultLibraryTab = "Saved"
    @AppStorage("library.autoLinkOnOpen") private var autoLinkOnOpen = false
    @AppStorage("library.layout") private var libraryLayout = ""
    @AppStorage("preferences.chapterAscending") private var chapterAscending = false
    @AppStorage("preferences.showCardStats") private var showCardStats = true
    @AppStorage("contentMode") private var mode: ContentMode = .all
    @AppStorage("keybinds.player.play") private var playKey = " "
    @AppStorage("keybinds.player.previous") private var previousKey = "["
    @AppStorage("keybinds.player.next") private var nextKey = "]"
    @AppStorage("player.autoplayNext") private var autoplayNext = true
    @AppStorage("player.autoSubtitles") private var autoSubtitles = true
    @AppStorage("player.subtitleLanguage") private var subtitleLanguage = ""
    @AppStorage("player.manualControls") private var manualControls = false
    @AppStorage("player.compactControls") private var compactControls = false
    @AppStorage("player.qualityScaling") private var qualityScaling = false
    @AppStorage("player.autoplay") private var playerAutoplay = true
    @AppStorage("player.speed") private var playerSpeed = 1.0
    @AppStorage("player.subtitleScale") private var subtitleScale = 1.0
    @AppStorage("player.subtitleHeight") private var subtitleHeight = 9.0
    @AppStorage("player.subtitleBackground") private var subtitleBackground = false
    @AppStorage("preferences.renderLimit") private var renderLimit = 48
    @Environment(AppLockStore.self) private var appLock
    @State private var serverVersion: String?
    @State private var serverURL: String?
    @State private var confirmation: Action?
    @State private var usage: StorageUsage?
    @State private var working = false
    @State private var notice: String?
    private let storage = SettingsStorage()

    enum Action: String, Identifiable {
        case history = "Clear reading history"
        case cache = "Clear cache"
        case reset = "Reset preferences"
        var id: Self { self }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                switch category {
                case .general: GeneralSettingsView(openExtensions: openExtensions)
                case .appearance: AppearanceSettingsContent()
                case .reader: ReaderSettingsView(preferences: readerPreferences, settingsPage: true)
                case .library: library
                case .storage: StorageSettingsContent()
                case .about: about
                case .player: player
                case .automation: AutomationSettingsContent()
                case .tracking: EmptyView()  // Hosted by TrackingSettingsDestination.
                case .performance: performance
                case .keybinds: KeybindsSettingsContent()
                case .folders: SettingsFoldersContent()
                case .content: ContentSettingsContent()
                case .server: ServerSettingsContent(openExtensions: openExtensions)
                case .auth: AuthSettingsContent()
                case .devTools: devTools

                }
                if let notice {
                    Text(notice).font(.system(size: 13)).foregroundStyle(GeneralStyle.faint)
                }

            }
            .padding(.horizontal, 20).padding(.top, 16).padding(
                .bottom, 24
            )
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .tracksNavigationScroll().accessibilityIdentifier("settings.scroll")
        .background(NavigationStyle.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            BackHeader(title: category.rawValue, backLabel: "Back to Settings") { dismiss() }
        }
        .font(.system(size: 13))
        .confirmationDialog(
            confirmation?.rawValue ?? "",
            isPresented: Binding(
                get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible
        ) {
            if let action = confirmation {
                Button(action.rawValue, role: .destructive) { Task { await perform(action) } }
            }
        } message: {
            switch confirmation {
            case .history:
                Text(
                    "Clear reading activity on this device. Saved titles and files will be kept.")
            case .cache:
                Text(
                    "Remove cached covers and temporary results. They will load again when needed. Your library, downloads, history, and source installations will be kept."
                )
            case .reset:
                Text(
                    "Restore preferences on this device. Saved titles and reading activity will be kept."
                )
            case nil: EmptyView()
            }
        }
        .task(id: category) {
            notice = nil
            if category == .storage { await refreshUsage() }
            if category == .devTools {
                serverURL = await Backend.shared.currentServerURL()?.absoluteString
            }
            if category == .about {
                do {
                    struct Result: Decodable, Sendable { struct About: Decodable, Sendable { let version: String }; let about: About }
                    let result: Result = try await BackendAPI.shared.graphql("{ about { version } }", requiresSourceRuntime: false)
                    serverVersion = result.about.version
                } catch { notice = "Couldn’t load the server version." }
            }
        }
    }

    private var library: some View {
        Group {
            GeneralSection("Display") {
                picker(
                    "Library mode", detail: "The active collection in Library.",
                    selection: Binding(
                        get: { mode.rawValue }, set: { mode = ContentMode(rawValue: $0) ?? .all }),
                    values: ContentMode.allCases.map {
                        ($0.rawValue, $0 == .all ? "All media" : $0.title)
                    })
                GeneralStyle.divider
                toggle(
                    "List layout", detail: "Show titles in rows instead of a cover grid.",
                    value: Binding(
                        get: { libraryLayout.isEmpty ? listLayout : libraryLayout == "list" },
                        set: {
                            listLayout = $0
                            libraryLayout = $0 ? "list" : "grid"
                        }))
                GeneralStyle.divider
                toggle(
                    "Show card stats", detail: "Show reading progress on Library cards.",
                    value: $showCardStats)
            }
            GeneralSection("Saved") {
                toggle("Show all in Saved", detail: "Include titles that are assigned to folders.", value: $showAllInSaved)
                GeneralStyle.divider
                toggle("Hide completed in Saved", detail: "Exclude finished titles from the Saved view.", value: $hideCompletedInSaved)
                GeneralStyle.divider
                picker("Default library view", detail: "Open this view when Library starts.", selection: $defaultLibraryTab, values: LibraryTab.allCases.map { ($0.rawValue, $0.rawValue) })
            }
            GeneralSection("Series") {
                toggle("Auto-link on open", detail: "Group saved titles with matching names.", value: $autoLinkOnOpen)
                GeneralStyle.divider
                toggle("Disable auto-complete", detail: "Keep finished titles in Reading instead of Completed.", value: $disableAutoComplete)
            }
            GeneralSection("Chapters") {
                toggle(
                    "Oldest chapters first", detail: "Default chapter order when opening a title.",
                    value: $chapterAscending)
            }
            GeneralSection("Reading activity") {
                actionRow("Clear reading history", symbol: "Trash", destructive: true) {
                    confirmation = .history
                }
            }
        }
    }

    private var about: some View {
        GeneralSection("Moku for iOS") {
            valueRow(
                "Version",
                value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                    as? String ?? "1.0")
            GeneralStyle.divider
            valueRow("Source runtime", value: "Tsunagu · on device")
            GeneralStyle.divider
            valueRow("Server version", value: serverVersion ?? "—")
            GeneralStyle.divider
            GeneralRow("Source code", detail: "") { Link("GitHub", destination: URL(string: "https://github.com/moku-project/Moku-iOS")!).buttonStyle(GeneralTextButtonStyle()) }
            GeneralStyle.divider
            GeneralRow("Release notes", detail: "") { Link("View", destination: URL(string: "https://github.com/moku-project/Moku-iOS/releases")!).buttonStyle(GeneralTextButtonStyle()) }
            GeneralStyle.divider
            GeneralRow("Report an issue", detail: "") { Link("Open", destination: URL(string: "https://github.com/moku-project/Moku-iOS/issues")!).buttonStyle(GeneralTextButtonStyle()) }

        }
    }

    private var player: some View {
        Group {
            GeneralSection("Playback") {
                toggle("Autoplay next episode", detail: "Continue when the current episode finishes.", value: $autoplayNext)
                GeneralStyle.divider
                toggle("Compact transport bar", detail: "Use a single row for playback controls.", value: $compactControls)
                GeneralStyle.divider
                toggle("Tap to toggle bar", detail: "Double-tap the video to show or hide controls.", value: $manualControls)
                GeneralStyle.divider
                toggle(
                    "Autoplay", detail: "Start playback when an episode opens.",
                    value: $playerAutoplay)
                GeneralStyle.divider
                GeneralRow("Playback speed", detail: "Default speed for new playback sessions.") {
                    ChoicePicker(
                        title: "", selection: $playerSpeed,
                        options: [0.75, 1, 1.25, 1.5, 1.75, 2].map { ($0, "\($0.formatted())×") }
                    )
                    .font(.system(size: 14)).accessibilityLabel("Playback speed")
                }
            }
            GeneralSection("Subtitles") {
                toggle("Enable by default", detail: "Select a subtitle track when playback opens.", value: $autoSubtitles)
                GeneralStyle.divider
                GeneralRow("Preferred language", detail: "Language name or code, such as en.") {
                    TextField("Language", text: $subtitleLanguage).textInputAutocapitalization(.never).autocorrectionDisabled().generalInput().frame(width: 140)
                }
                GeneralStyle.divider
                GeneralRow("Text size", detail: "Scale subtitle text.") {
                    ChoicePicker(
                        title: "", selection: $subtitleScale,
                        options: [0.75, 1, 1.25, 1.5, 2].map { ($0, "\(Int($0 * 100))%") }
                    )
                    .font(.system(size: 14)).accessibilityLabel("Subtitle text size")
                }
                GeneralStyle.divider
                GeneralRow("Bottom offset", detail: "Distance from the bottom of the video.") {
                    ChoicePicker(
                        title: "", selection: $subtitleHeight,
                        options: [3.0, 6, 9, 12, 15, 20].map { ($0, "\(Int($0))%") }
                    )
                    .font(.system(size: 14)).accessibilityLabel("Subtitle bottom offset")
                }
                GeneralStyle.divider
                toggle(
                    "Subtitle background", detail: "Show a background behind subtitle text.",
                    value: $subtitleBackground)
            }
            GeneralSection("Rendering") {
                toggle("High-quality scaling", detail: "Use trilinear video scaling.", value: $qualityScaling)
            }
        }
    }
    private func readerToggle(
        _ title: String, detail: String, key: WritableKeyPath<ReaderBehaviour, Bool>
    ) -> some View {
        toggle(
            title, detail: detail,
            value: Binding(
                get: { readerPreferences.document.behaviour[keyPath: key] },
                set: { readerPreferences.document.behaviour[keyPath: key] = $0 }))
    }
    private var performance: some View {
        Group {
            GeneralSection("Library") {
                GeneralRow("Titles per page", detail: "Limit the number of library cards rendered at once.") {
                    ChoicePicker(title: "", selection: $renderLimit, options: [12, 24, 48, 96, 144, 200].map { ($0, String($0)) }).font(.system(size: 14))
                }
            }
            CacheSettingsContent()
            GeneralSection("Reader") {
                GeneralRow("Pages to preload", detail: "Load upcoming pages while reading.") {
                    ChoicePicker(
                        title: "",
                        selection: Binding(
                            get: { readerPreferences.document.behaviour.preloadPages },
                            set: { readerPreferences.document.behaviour.preloadPages = $0 }),
                        options: (0...10).map { ($0, String($0)) }
                    )
                    .font(.system(size: 14)).accessibilityLabel("Pages to preload")
                }
            }
            GeneralSection("Interface") {
                toggle(
                    "Interface animations",
                    detail: "Tab transitions and button feedback. Respects Reduce Motion.",
                    value: $animations
                )
                GeneralStyle.divider
                toggle(
                    "Solid interface", detail: "Use opaque navigation and menus instead of glass.",
                    value: $solidSurfaces)
            }
        }
    }
    private var devTools: some View {
        Group {
            GeneralSection("Testing") {
                GeneralRow("Idle screen", detail: "Preview the inactivity screen.") {
                    Button("Preview") { NotificationCenter.default.post(name: .mokuPreviewIdle, object: nil) }.buttonStyle(GeneralTextButtonStyle())
                }
                GeneralStyle.divider
                GeneralRow("App lock", detail: "Test the configured PIN or biometric unlock.") {
                    Button("Lock") { appLock.lock() }.buttonStyle(GeneralTextButtonStyle()).disabled(!appLock.enabled)
                }
                GeneralStyle.divider
                GeneralRow("Notice", detail: "Test an in-app notice.") {
                    Button("Show") { notice = "Test notice." }.buttonStyle(GeneralTextButtonStyle())
                }
            }
            GeneralSection("Runtime") {
                valueRow("Bundled server", value: serverURL == nil ? "Stopped" : "Running")
                GeneralStyle.divider
                valueRow("System", value: "iOS \(UIDevice.current.systemVersion)")
                GeneralStyle.divider
                valueRow(
                    "Build",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                        ?? "1")
                GeneralStyle.divider
                GeneralRow("Runtime status", detail: "Check the bundled server.") {
                    Button("Refresh") {
                        Task { serverURL = await Backend.shared.currentServerURL()?.absoluteString }
                    }
                    .buttonStyle(GeneralTextButtonStyle())
                }
            }
            GeneralSection("Cache") {
                actionRow(
                    "Clear cache", symbol: "ArrowsClockwise",
                    detail:
                        "Remove cached covers and temporary results. Library, downloads, and history are kept."
                ) { confirmation = .cache }.disabled(
                    working)
            }
        }
    }

    private func toggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        GeneralRow(title, detail: detail) {
            Toggle(title, isOn: value).toggleStyle(GeneralToggleStyle())
                .accessibilityIdentifier(title)
        }
    }
    private func picker(
        _ title: String, detail: String, selection: Binding<String>, values: [(String, String)]
    ) -> some View {
        GeneralRow(title, detail: detail) {
            ChoicePicker(title: "", selection: selection, options: values)
                .font(.system(size: 14))
                .accessibilityLabel(title).accessibilityValue(selection.wrappedValue)
                .accessibilityIdentifier("settings.picker.\(title)")
        }
    }
    private func valueRow(_ title: String, value: String) -> some View {
        GeneralRow(title, detail: "") {
            if value == "…" {
                SkeletonBlock(width: 72, height: 14).skeletonMotion(
                    "Storage usage is being calculated")
            } else {
                Text(value).font(.system(size: 14)).foregroundStyle(GeneralStyle.text)
                    .multilineTextAlignment(.trailing).frame(maxWidth: 160)
            }
        }
    }
    private func actionRow(
        _ title: String, symbol: String, destructive: Bool = false, detail: String = "",
        action: @escaping () -> Void
    ) -> some View {
        GeneralRow(title, detail: detail) {
            Button(
                destructive ? (title == "Reset preferences" ? "Reset" : "Clear") : "Clear",
                action: action
            )
            .buttonStyle(GeneralTextButtonStyle())
            .accessibilityLabel(title)
        }
    }
    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
    private func refreshUsage() async {
        do { usage = try await storage.usage() } catch {
            notice = "Couldn’t measure storage. Try again."
        }
    }
    private func perform(_ action: Action) async {
        working = true
        defer { working = false }
        switch action {
        case .history:
            await home.clearHistory()
            notice = home.storageError ?? "Reading history cleared."
        case .cache:
            do {
                await BackendAPI.shared.clearContentCache()
                SkeletonVisits.shared.clear()
                try await storage.clearCovers()
                await refreshUsage()
                notice = "Cache cleared."
            } catch { notice = "Couldn’t clear all cached content. Try again." }
        case .reset:
            interfaceScale = 100
            idleTimeout = 5
            language = "all"
            animations = true
            theme = "midnight"
            solidSurfaces = false
            cropCovers = true
            listLayout = false
            libraryLayout = "grid"
            chapterAscending = false
            showCardStats = true
            mode = .all
            playerAutoplay = true
            playerSpeed = 1
            subtitleScale = 1
            subtitleHeight = 9
            subtitleBackground = false
            playKey = " "
            previousKey = "["
            nextKey = "]"
            readerPreferences.document.global = MangaReadingSettings()
            readerPreferences.document.behaviour = ReaderBehaviour()
            notice = "Preferences reset."
        }
    }
}

private struct SettingsFoldersContent: View {
    @Environment(LibraryStore.self) private var library
    @State private var draft = FolderViewModel()
    @State private var editing: LibraryFolder?
    @State private var deleting: LibraryFolder?
    @State private var naming = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        GeneralSection("Library folders") {
            GeneralRow("New folder", detail: "Organize saved titles.") {
                Button("Create") {
                    editing = nil
                    draft.name = ""
                    naming = true
                }.buttonStyle(GeneralTextButtonStyle())
            }
            ForEach(library.organization.folders) { folder in
                GeneralStyle.divider
                GeneralRow(folder.name, detail: "\(folder.entryIDs.count) titles") {
                    OverflowMenu {
                        Button("Rename") {
                            editing = folder
                            draft.name = folder.name
                            naming = true
                        }
                        Button(folder.hidden == true ? "Show in library" : "Hide from library") { update(folder) { $0.hidden = !($0.hidden ?? false) } }
                        Button(folder.includeInUpdate == false ? "Include in updates" : "Exclude from updates") { update(folder) { $0.includeInUpdate = !($0.includeInUpdate ?? true) } }
                        Button(folder.includeInDownload == false ? "Include in downloads" : "Exclude from downloads") { update(folder) { $0.includeInDownload = !($0.includeInDownload ?? true) } }
                        Button("Move up") { move(folder, offset: -1) }.disabled(library.organization.folders.first?.id == folder.id)
                        Button("Move down") { move(folder, offset: 1) }.disabled(library.organization.folders.last?.id == folder.id)
                        Button("Delete", role: .destructive) { deleting = folder }
                    } label: {
                        Text("Manage").font(.system(size: 14)).foregroundStyle(GeneralStyle.text)
                            .frame(minHeight: 44)
                    }.accessibilityLabel("Manage \(folder.name)")
                }
            }
            if let error {
                Text(error).font(.system(size: 13)).foregroundStyle(GeneralStyle.faint).padding(
                    .vertical, 14)
            }
        }
        .disabled(saving)
        .task {
            await library.loadOrganization()
            error = library.error
        }
        .alert(editing == nil ? "Create folder" : "Rename folder", isPresented: $naming) {
            TextField("Folder name", text: $draft.name)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await save() } }
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(
            "Delete folder?",
            isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete folder", role: .destructive) {
                guard let folder = deleting else { return }
                Task {
                    saving = true
                    defer { saving = false }
                    var next = library.organization
                    next.folders.removeAll { $0.id == folder.id }
                    if !(await library.saveOrganization(next)) { error = library.error }
                    deleting = nil
                }
            }
        } message: {
            Text("Titles will remain in your library.")
        }
    }
    private func update(_ folder: LibraryFolder, change: @escaping (inout LibraryFolder) -> Void) {
        Task {
            saving = true
            defer { saving = false }
            var next = library.organization
            guard let index = next.folders.firstIndex(where: { $0.id == folder.id }) else { return }
            change(&next.folders[index])
            if !(await library.saveOrganization(next)) { error = library.error }
        }
    }
    private func move(_ folder: LibraryFolder, offset: Int) {
        Task {
            saving = true
            defer { saving = false }
            var next = library.organization
            guard let index = next.folders.firstIndex(where: { $0.id == folder.id }), next.folders.indices.contains(index + offset) else { return }
            next.folders.swapAt(index, index + offset)
            if !(await library.saveOrganization(next)) { error = library.error }
        }
    }
    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        if let editing {
            var next = library.organization
            guard let index = next.folders.firstIndex(where: { $0.id == editing.id }) else {
                return
            }
            next.folders[index].name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !(await library.saveOrganization(next)) { error = library.error }
        } else if await draft.create(in: library) == nil {
            error = draft.error
        }
    }
}

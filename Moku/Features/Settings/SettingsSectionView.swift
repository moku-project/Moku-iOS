import SwiftUI

struct SettingsSectionView: View {
    @AppStorage("onboarding.completed") private var onboarded = true
    let category: SettingsCategory
    @Environment(\.dismiss) private var dismiss

    let openExtensions: () -> Void
    @Environment(ReadingHistory.self) private var home
    @Environment(ReaderPreferences.self) private var readerPreferences
    @AppStorage("preferences.language") private var language = "all"
    @AppStorage("preferences.interfaceScale") private var interfaceScale = 100.0
    @AppStorage("preferences.idleTimeout") private var idleTimeout = 5
    @AppStorage("preferences.animations") private var animations = true
    @AppStorage("preferences.theme") private var theme = "dark"
    @AppStorage("preferences.solidSurfaces") private var solidSurfaces = false
    @AppStorage("preferences.cropCovers") private var cropCovers = true
    @AppStorage("library.listLayout") private var listLayout = false
    @AppStorage("library.showAllInSaved") private var showAllInSaved = true
    @AppStorage("library.hideCompletedInSaved") private var hideCompletedInSaved = false
    @AppStorage("library.disableAutoComplete") private var disableAutoComplete = false
    @AppStorage("library.defaultTab") private var defaultLibraryTab = "Saved"
    @Environment(LibraryStore.self) private var libraryStore
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
    @AppStorage("player.backgroundAudio") private var backgroundAudio = true
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
    @State private var reportOpen = false
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
        page
            .navigationTitle(category.rawValue)
            .navigationBarTitleDisplayMode(.inline)
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
                        "Clear reading activity on this device. Saved titles and files will be kept."
                    )
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
            .sheet(isPresented: $reportOpen) { BugReportSheet() }
            .task(id: category) {
                notice = nil
                if category == .devTools {
                    serverURL = await Backend.shared.currentServerURL()?.absoluteString
                }
                if category == .about {
                    do {
                        struct Result: Decodable, Sendable {
                            struct About: Decodable, Sendable { let version: String }
                            let about: About
                        }
                        let result: Result = try await BackendAPI.shared.graphql(
                            "{ about { version } }", requiresSourceRuntime: false)
                        serverVersion = result.about.version
                    } catch { notice = "Couldn’t load the server version." }
                }
            }
    }

    @ViewBuilder private var page: some View {
        switch category {
        case .general: GeneralSettingsView(openExtensions: openExtensions)
        case .appearance: AppearanceSettingsContent()
        case .reader:
            SettingsForm { ReaderSettingsView(preferences: readerPreferences) }
        case .library:
            SettingsForm {
                library
                SettingsNotice(text: notice)
            }
        case .storage: StorageSettingsContent()
        case .about:
            SettingsForm {
                about
                SettingsNotice(text: notice)
            }
        case .player: SettingsForm { player }
        case .automation: AutomationSettingsContent()
        case .sync: SyncSettingsContent()
        case .tracking: EmptyView()  // Hosted by TrackingSettingsDestination.
        case .performance:
            SettingsForm {
                performance
                SettingsNotice(text: notice)
            }
        case .keybinds: KeybindsSettingsContent()
        case .folders: SettingsFoldersContent()
        case .content: ContentSettingsContent()
        case .server: ServerSettingsContent(openExtensions: openExtensions)
        case .auth: AuthSettingsContent()
        case .devTools:
            SettingsForm {
                devTools
                SettingsNotice(text: notice)
            }
        }
    }

    @ViewBuilder private var library: some View {
        Section("Display") {
            SettingsPicker(
                "Library mode", detail: "The active collection in Library.",
                selection: $mode,
                options: ContentMode.allCases.map { ($0, $0 == .all ? "All media" : $0.title) })
            SettingsToggle(
                "List layout", detail: "Show titles in rows instead of a cover grid.",
                isOn: Binding(
                    get: { libraryLayout.isEmpty ? listLayout : libraryLayout == "list" },
                    set: {
                        listLayout = $0
                        libraryLayout = $0 ? "list" : "grid"
                    }))
            SettingsToggle(
                "Show card stats", detail: "Show reading progress on Library cards.",
                isOn: $showCardStats)
        }
        Section("Saved") {
            SettingsToggle(
                "Show all in Saved", detail: "Include titles that are assigned to folders.",
                isOn: $showAllInSaved)
            SettingsToggle(
                "Hide completed in Saved", detail: "Exclude finished titles from the Saved view.",
                isOn: $hideCompletedInSaved)
            SettingsPicker(
                "Default library view", detail: "Open this view when Library starts.",
                selection: $defaultLibraryTab,
                options: LibraryTab.allCases.map { ($0.rawValue, $0.rawValue) }
                    + libraryStore.organization.folders.map {
                        ("folder:\($0.id.uuidString)", $0.name)
                    })
        }
        Section("Series") {
            SettingsToggle(
                "Auto-link on open", detail: "Group saved titles with matching names.",
                isOn: $autoLinkOnOpen)
            SettingsToggle(
                "Disable auto-complete",
                detail: "Keep finished titles in Reading instead of Completed.",
                isOn: $disableAutoComplete)
        }
        Section("Chapters") {
            SettingsToggle(
                "Oldest chapters first", detail: "Default chapter order when opening a title.",
                isOn: $chapterAscending)
        }
        Section {
            Button("Clear reading history", role: .destructive) { confirmation = .history }
                .disabled(working)
        } header: {
            Text("Reading activity")
        } footer: {
            Text("Saved titles and downloaded files are kept.")
        }
    }

    @ViewBuilder private var about: some View {
        Section("Moku for iOS") {
            LabeledContent(
                "Version",
                value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                    as? String ?? "1.0")
            LabeledContent("Source runtime", value: "Tsunagu · on device")
            LabeledContent("Server version", value: serverVersion ?? "—")
        }
        Section {
            Link(
                "Source code", destination: URL(string: "https://github.com/moku-project/Moku-iOS")!
            )
            Link(
                "Release notes",
                destination: URL(string: "https://github.com/moku-project/Moku-iOS/releases")!)
            SettingsLinkRow(
                "Report an issue", detail: "Bug or feature request, with the settings you choose."
            ) { reportOpen = true }
        }
    }

    @ViewBuilder private var player: some View {
        Section("Playback") {
            SettingsToggle(
                "Autoplay next episode", detail: "Continue when the current episode finishes.",
                isOn: $autoplayNext)
            SettingsToggle(
                "Compact transport bar", detail: "Use a single row for playback controls.",
                isOn: $compactControls)
            SettingsToggle(
                "Tap to toggle bar", detail: "Double-tap the video to show or hide controls.",
                isOn: $manualControls)
            SettingsToggle(
                "Autoplay", detail: "Start playback when an episode opens.", isOn: $playerAutoplay)
            SettingsPicker(
                "Playback speed", detail: "Default speed for new playback sessions.",
                selection: $playerSpeed,
                options: [0.75, 1, 1.25, 1.5, 1.75, 2].map { ($0, "\($0.formatted())×") })
        }
        Section("Subtitles") {
            SettingsToggle(
                "Enable by default", detail: "Select a subtitle track when playback opens.",
                isOn: $autoSubtitles)
            LabeledContent {
                TextField("Language", text: $subtitleLanguage, prompt: Text("en"))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } label: {
                SettingsLabel("Preferred language", detail: "Language name or code, such as en.")
            }
            SettingsPicker(
                "Text size", detail: "Scale subtitle text.", selection: $subtitleScale,
                options: [0.75, 1, 1.25, 1.5, 2].map { ($0, "\(Int($0 * 100))%") })
            SettingsPicker(
                "Bottom offset", detail: "Distance from the bottom of the video.",
                selection: $subtitleHeight,
                options: [3.0, 6, 9, 12, 15, 20].map { ($0, "\(Int($0))%") })
            SettingsToggle(
                "Subtitle background", detail: "Show a background behind subtitle text.",
                isOn: $subtitleBackground)
        }
        Section {
            SettingsToggle("Keep playing in the background", isOn: $backgroundAudio)
        } header: {
            Text("Background")
        } footer: {
            Text(
                "Keeps playing in the background and in Picture in Picture."
            )
        }
        Section("Rendering") {
            SettingsToggle(
                "High-quality scaling", detail: "Use trilinear video scaling.",
                isOn: $qualityScaling)
        }
    }

    @ViewBuilder private var performance: some View {
        Section {
            SettingsPicker(
                "Titles per page", selection: $renderLimit,
                options: [12, 24, 48, 96, 144, 200].map { ($0, String($0)) })
        } header: {
            Text("Library")
        } footer: {
            Text("Limit the number of library cards rendered at once.")
        }
        CacheSettingsContent()
        Section {
            let preload = Binding(
                get: { readerPreferences.document.behaviour.preloadPages },
                set: { readerPreferences.document.behaviour.preloadPages = $0 })
            Stepper(value: preload, in: 0...10) {
                LabeledContent("Pages to preload", value: String(preload.wrappedValue))
            }
            .accessibilityLabel("Pages to preload")
            .accessibilityValue(String(preload.wrappedValue))
        } header: {
            Text("Reader")
        } footer: {
            Text("Load upcoming pages while reading.")
        }
        Section("Interface") {
            SettingsToggle(
                "Interface animations",
                detail: "Tab transitions and button feedback. Respects Reduce Motion.",
                isOn: $animations)
            SettingsToggle(
                "Solid interface", detail: "Use opaque navigation and menus instead of glass.",
                isOn: $solidSurfaces)
        }
    }

    @ViewBuilder private var devTools: some View {
        Section("Testing") {
            Button {
                NotificationCenter.default.post(name: .mokuPreviewIdle, object: nil)
            } label: {
                SettingsLabel("Preview idle screen", detail: "Preview the inactivity screen.")
            }
            Button {
                appLock.lock()
            } label: {
                SettingsLabel("Lock app", detail: "Test the configured PIN or biometric unlock.")
            }
            .disabled(!appLock.enabled)
            Button {
                Toaster.shared.show(
                    "Test toast", detail: "Toasts confirm actions without blocking.")
            } label: {
                SettingsLabel("Show toast", detail: "Show a test toast.")
            }
            Button {
                onboarded = false
            } label: {
                SettingsLabel("Replay onboarding", detail: "Show the welcome screens again.")
            }
        }
        Section("Runtime") {
            LabeledContent("Bundled server", value: serverURL == nil ? "Stopped" : "Running")
            LabeledContent("System", value: "iOS \(UIDevice.current.systemVersion)")
            LabeledContent(
                "Build",
                value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
            )
            Button("Refresh runtime status") {
                Task { serverURL = await Backend.shared.currentServerURL()?.absoluteString }
            }
        }
        Section {
            Button("Clear cache", role: .destructive) { confirmation = .cache }
                .disabled(working)
        } header: {
            Text("Cache")
        } footer: {
            Text(
                "Library, downloads and history are kept."
            )
        }
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
    private func perform(_ action: Action) async {
        working = true
        defer { working = false }
        switch action {
        case .history:
            await home.clear()
            notice = home.error ?? "Reading history cleared."
        case .cache:
            do {
                await BackendAPI.shared.clearContentCache()
                SkeletonVisits.shared.clear()
                try await storage.clearCovers()
                notice = "Cache cleared."
            } catch { notice = "Couldn’t clear all cached content. Try again." }
        case .reset:
            interfaceScale = 100
            idleTimeout = 5
            language = "all"
            animations = true
            theme = "dark"
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
        SettingsForm {
            Section {
                ForEach(library.organization.folders) { folder in
                    Menu {
                        actions(for: folder)
                    } label: {
                        HStack {
                            SettingsLabel(folder.name, detail: folderDetail(folder))
                            Spacer(minLength: 8)
                            Image(systemName: "ellipsis.circle").foregroundStyle(
                                NavigationStyle.accent)
                        }
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Manage \(folder.name)")
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleting = folder }
                        Button("Rename") { rename(folder) }
                    }
                    .contextMenu { actions(for: folder) }
                }
                Button {
                    editing = nil
                    draft.name = ""
                    naming = true
                } label: {
                    Label("New folder", systemImage: "folder.badge.plus")
                }
            } header: {
                Text("Library folders")
            } footer: {
                Text("Organize saved titles.")
            }
            SettingsNotice(text: error)
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
    private func rename(_ folder: LibraryFolder) {
        editing = folder
        draft.name = folder.name
        naming = true
    }
    @ViewBuilder private func actions(for folder: LibraryFolder) -> some View {
        Button("Rename", systemImage: "pencil") { rename(folder) }
        Button(
            folder.hidden == true ? "Show in library" : "Hide from library",
            systemImage: folder.hidden == true ? "eye" : "eye.slash"
        ) { update(folder) { $0.hidden = !($0.hidden ?? false) } }
        Button(
            folder.includeInUpdate == false ? "Include in updates" : "Exclude from updates",
            systemImage: "arrow.clockwise"
        ) { update(folder) { $0.includeInUpdate = !($0.includeInUpdate ?? true) } }
        Button(
            folder.includeInDownload == false ? "Include in downloads" : "Exclude from downloads",
            systemImage: "arrow.down.circle"
        ) { update(folder) { $0.includeInDownload = !($0.includeInDownload ?? true) } }
        Menu("Show for") {
            ForEach([ContentMode.manga, .novels, .anime]) { type in
                let on = folder.contentTypes?.contains(type) == true
                Button {
                    update(folder) { value in
                        var types = value.contentTypes ?? []
                        if on { types.removeAll { $0 == type } } else { types.append(type) }
                        value.contentTypes = types.isEmpty ? nil : types
                    }
                } label: {
                    if on { Label(type.title, systemImage: "checkmark") } else { Text(type.title) }
                }
            }
        }
        Button("Move up", systemImage: "arrow.up") { move(folder, offset: -1) }.disabled(
            library.organization.folders.first?.id == folder.id)
        Button("Move down", systemImage: "arrow.down") { move(folder, offset: 1) }.disabled(
            library.organization.folders.last?.id == folder.id)
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = folder }
    }
    private func folderDetail(_ folder: LibraryFolder) -> String {
        let count = "\(folder.entryIDs.count) title\(folder.entryIDs.count == 1 ? "" : "s")"
        guard let types = folder.contentTypes, !types.isEmpty else { return count }
        return "\(count) · \(types.map(\.title).joined(separator: ", ")) only"
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
            guard let index = next.folders.firstIndex(where: { $0.id == folder.id }),
                next.folders.indices.contains(index + offset)
            else { return }
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

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
    @AppStorage("preferences.chapterAscending") private var chapterAscending = false
    @AppStorage("preferences.showCardStats") private var showCardStats = true
    @AppStorage("contentMode") private var mode: ContentMode = .all
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
            VStack(alignment: .leading, spacing: 22) {
                switch category {
                case .general: GeneralSettingsView(openExtensions: openExtensions)
                case .appearance: appearance
                case .reader: ReaderSettingsView(preferences: readerPreferences)
                case .library: library
                case .storage: storageContent
                case .about: about
                default:
                    Text(category.availability)
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                }
                if let notice { Text(notice).font(.system(size: 12)).foregroundStyle(.secondary) }

            }
            .padding(.horizontal, 20).padding(.top, category == .general ? 16 : 12).padding(
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
        }
    }

    private var appearance: some View {
        Group {
            SettingsGroup("Theme", symbol: "PaintBrush") {
                picker(
                    "App theme", detail: "Applies throughout Moku.", selection: $theme,
                    values: [
                        ("midnight", "Midnight"), ("charcoal", "Charcoal"), ("sepia", "Sepia"),
                    ])
                Divider()
                toggle(
                    "Solid interface", detail: "Use opaque navigation and menus instead of glass.",
                    value: $solidSurfaces)
            }
            SettingsGroup("Covers", symbol: "ImageSquare") {
                toggle(
                    "Crop cover images",
                    detail: "Fill the cover frame instead of fitting the whole image.",
                    value: $cropCovers)
            }
            Text("Themes and display preferences are saved on this device.").font(
                .system(size: 12)
            )
            .foregroundStyle(.secondary)
        }
    }

    private var library: some View {
        Group {
            SettingsGroup("Display", symbol: "Books") {
                picker(
                    "Library mode", detail: "The active collection in Library.",
                    selection: Binding(
                        get: { mode.rawValue }, set: { mode = ContentMode(rawValue: $0) ?? .all }),
                    values: ContentMode.allCases.map {
                        ($0.rawValue, $0 == .all ? "All media" : $0.title)
                    })
                Divider()
                toggle(
                    "List layout", detail: "Show titles in rows instead of a cover grid.",
                    value: $listLayout)
                Divider()
                toggle(
                    "Show card stats", detail: "Show reading progress on Library cards.",
                    value: $showCardStats)
            }
            SettingsGroup("Chapters", symbol: "ListNumbers") {
                toggle(
                    "Oldest chapters first", detail: "Default chapter order when opening a title.",
                    value: $chapterAscending)
            }
            SettingsGroup("Reading activity", symbol: "ClockCounterClockwise") {
                actionRow("Clear reading history", symbol: "Trash", destructive: true) {
                    confirmation = .history
                }
            }
        }
    }

    private var storageContent: some View {
        Group {
            SettingsGroup("On this device", symbol: "HardDrives") {
                valueRow(
                    "App data",
                    value: usage.map { bytes($0.total) } ?? (notice == nil ? "…" : "Unavailable"))
                Divider()
                valueRow(
                    "Cached content",
                    value: usage.map { bytes($0.covers) } ?? (notice == nil ? "…" : "Unavailable"))
                Divider()
                valueRow(
                    "Available space",
                    value: usage.map { bytes($0.available) }
                        ?? (notice == nil ? "…" : "Unavailable"))
                Divider()
                actionRow("Clear cache", symbol: "ArrowsClockwise") { confirmation = .cache }
                    .disabled(working)
            }
            .firstLoadSkeleton("storage", loading: usage == nil && notice == nil, style: .settings)
            Text(
                "Cached covers and temporary results are stored in the iOS app sandbox. Clearing cache keeps your library, downloads, and history."
            )
            .font(.system(size: 12)).foregroundStyle(.secondary)
            SettingsGroup("Preferences", symbol: "Sliders") {
                actionRow("Reset preferences", symbol: "ArrowCounterClockwise", destructive: true) {
                    confirmation = .reset
                }
            }
        }
    }

    private var about: some View {
        SettingsGroup("Moku for iOS", symbol: "Info") {
            valueRow(
                "Version",
                value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                    as? String ?? "1.0")
            Divider()
            valueRow("Source runtime", value: "Tsunagu · on device")
            Divider()
            Text(
                "Your library and activity live in this app’s private storage. No server account or sign-in is required."
            )
            .font(.system(size: 12)).foregroundStyle(.secondary).frame(
                maxWidth: .infinity, alignment: .leading
            ).padding(.vertical, 12)
        }
    }

    private func rowLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13)).foregroundStyle(.primary)
            if !detail.isEmpty {
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
            }
        }.padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func toggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) { rowLabel(title, detail: detail) }.tint(NavigationStyle.accent)
            .accessibilityIdentifier(title)
    }
    private func picker(
        _ title: String, detail: String, selection: Binding<String>, values: [(String, String)]
    ) -> some View {
        HStack(spacing: 12) {
            rowLabel(title, detail: detail)
            ChoicePicker(title: "", selection: selection, options: values)
                .buttonStyle(.plain)
                .accessibilityLabel(title).accessibilityValue(selection.wrappedValue)
                .accessibilityIdentifier("settings.picker.\(title)")
        }
    }
    private func valueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Group {
                if value == "…" {
                    SkeletonBlock(width: 72, height: 14).skeletonMotion(
                        "Storage usage is being calculated")
                } else {
                    Text(value).foregroundStyle(.secondary)
                }
            }
        }.font(.system(size: 12)).frame(minHeight: 46)
    }
    private func actionRow(
        _ title: String, symbol: String, destructive: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, phosphor: symbol)
                Spacer()
                PhosphorIcon("CaretRight").iconSize(10)
            }
            .font(.system(size: 13)).foregroundStyle(destructive ? .red : .primary)
            .frame(minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain)
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
            chapterAscending = false
            showCardStats = true
            mode = .all
            notice = "Preferences reset."
        }
    }
}

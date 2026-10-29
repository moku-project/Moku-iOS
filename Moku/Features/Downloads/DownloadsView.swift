import SwiftUI

struct DownloadsView: View {
    @State var model: DownloadsViewModel
    var isActive = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var section: DownloadsSection = .all
    @State private var history = false
    @State private var typePresented = false
    @State private var expanded: Set<String> = []
    @State private var confirmClear = false
    @State private var menuLevel: RadialMenuLevel = .closed
    @State private var viewPresented = false
    @Environment(\.navigationContentBottomInset) private var bottomInset
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("preferences.animations") private var animations = true
    @AppStorage("downloads.autoRetry") private var autoRetry = false
    private var reduceMotion: Bool { systemReduceMotion || !animations }

    private var emptyDetail: String {
        if history { return "Finished and removed downloads will appear here." }
        switch section {
        case .failed: return "No failed downloads."
        case .completed: return "Downloaded chapters and episodes appear here for offline reading."
        case .all, .pending:
            return "Download chapters or episodes from a title’s page to read and watch offline."
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                viewSelector.zIndex(3)
                Group {
                    if model.count(section: section, history: history) == 0 {
                        GeometryReader { geometry in
                            ScrollView {
                                VStack(spacing: 10) {
                                    Text("Nothing here yet").font(.title2.bold())
                                    Text(emptyDetail).font(.subheadline).foregroundStyle(.secondary)
                                }
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: max(160, geometry.size.height - 120))
                            }.tracksNavigationScroll()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if section == .pending {
                                    HStack {
                                        Label(
                                            model.isPaused ? "Paused" : queueStatus,
                                            phosphor: model.isPaused
                                                ? "PauseCircle" : "DownloadSimple")
                                        Spacer()
                                        Text(
                                            "\(model.count(section: section, history: history)) chapters"
                                        )
                                    }.font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(model.groups(section: section, history: history)) { group in
                                    DownloadGroupView(
                                        group: group, model: model, section: section,
                                        expanded: expanded.contains(group.id),
                                        reduceMotion: reduceMotion,
                                        toggle: {
                                            if !expanded.insert(group.id).inserted {
                                                expanded.remove(group.id)
                                            }
                                        })
                                }
                            }.padding(.horizontal, NavigationStyle.pagePadding).padding(.top, 4)
                        }.accessibilityIdentifier("downloads.scroll").tracksNavigationScroll()
                    }
                }
                .environment(\.navigationContentBottomInset, bottomInset + 68)
                .pillBackdrop(viewPresented || typePresented)
                .opacity(menuLevel == .closed ? 1 : 0.18)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: menuLevel)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.16),
                    value: viewPresented || typePresented
                )
                .overlay {
                    if viewPresented || typePresented || menuLevel != .closed {
                        Color.black.opacity(0.001).contentShape(Rectangle())
                            .onTapGesture { dismissTools() }
                            .accessibilityLabel("Dismiss download tools")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { dismissTools() }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                RadialMenu(
                    level: $menuLevel, reduceMotion: reduceMotion, actions: radialActions,
                    accessibilityPrefix: "downloads", toolsTitle: "Downloads"
                )
                .pillBackdrop(viewPresented || typePresented)
                .padding(.trailing, max(16, (geometry.size.width - 336) / 2))
                .padding(.bottom, bottomInset + 12)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: viewPresented)
            .onChange(of: menuLevel) { _, level in
                if level != .closed {
                    viewPresented = false
                    typePresented = false
                }
            }
        }
        .onDisappear { dismissTools() }
        .task(id: isActive && scenePhase == .active) {
            guard isActive && scenePhase == .active else { return }
            model.autoRetry = autoRetry
            while !Task.isCancelled {
                await model.refresh()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .onChange(of: autoRetry) { _, value in model.autoRetry = value }
        .onChange(of: model.autoRetry) { _, value in autoRetry = value }
        .alert("Downloads", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
        .confirmationDialog(
            "Clear \(section.rawValue.lowercased()) downloads?",
            isPresented: $confirmClear, titleVisibility: .visible
        ) {
            Button("Clear \(section.rawValue.lowercased())", role: .destructive) {
                model.clear(section: section, history: history)
            }
        } message: {
            Text(
                history && (section == .completed || section == .all)
                    ? "Remove completed records from history. Downloaded files will be kept."
                    : "Remove all \(section.rawValue.lowercased()) chapters from this view.")
        }
    }

    private var queueStatus: String {
        model.entries.contains { $0.status == .downloading } ? "Downloading" : "Waiting"
    }

    private var viewSelector: some View {
        HStack {
            IconRail(
                title: history ? "History" : "Queue",
                symbol: history ? "ClockCounterClockwise" : "DownloadSimple",
                isPresented: viewPresented, itemCount: 1, reduceMotion: reduceMotion,
                toggle: {
                    menuLevel = .closed
                    typePresented = false
                    viewPresented.toggle()
                }
            ) {
                IconRailRow(
                    title: history ? "Queue" : "History",
                    symbol: history ? "DownloadSimple" : "ClockCounterClockwise",
                    selected: false
                ) {
                    history.toggle()
                    section = .all
                    expanded = []
                    dismissTools()
                }
            }
            .accessibilityLabel("Downloads view")
            .accessibilityValue(history ? "History" : "Queue")
            .pillBackdrop(typePresented)
            .accessibilityIdentifier("downloads.activeView")
            Spacer(minLength: 8)
            IconRail(
                title: section.rawValue, symbol: section.symbol,
                isPresented: typePresented, itemCount: DownloadsSection.allCases.count - 1,
                reduceMotion: reduceMotion,
                iconOnly: true, trailing: true,
                toggle: {
                    menuLevel = .closed
                    viewPresented = false
                    typePresented.toggle()
                }
            ) {
                ForEach(DownloadsSection.allCases.filter { $0 != section }) { choice in
                    downloadViewRow(choice)
                }
            }
            .accessibilityLabel("Download status")
            .accessibilityValue(section.rawValue)
            .pillBackdrop(viewPresented)
            .accessibilityIdentifier("downloads.status")
        }
        .accessibilityAction(.escape) { dismissTools() }
        .padding(.horizontal, NavigationStyle.pagePadding).padding(.top, 4)
    }

    private func downloadViewRow(_ choice: DownloadsSection) -> some View {
        IconRailRow(
            title: choice.rawValue, symbol: choice.symbol, selected: false, iconOnRight: true
        ) {
            section = choice
            expanded = []
            dismissTools()
        }
        .accessibilityIdentifier("downloads.\(choice.rawValue.lowercased())")
    }

    private var radialActions: [RadialAction] {
        guard menuLevel != .closed else { return [] }
        var actions: [RadialAction] = [
            .init(title: model.autoRetry ? "Auto retry on" : "Auto retry off", symbol: "Repeat") {
                dismissTools()
                model.autoRetry.toggle()
            }
        ]
        if section == .failed {
            actions.append(
                .init(
                    title: "Retry all", symbol: "ArrowClockwise",
                    isEnabled: model.count(section: .failed, history: history) > 0
                ) {
                    dismissTools()
                    model.retry()
                    history = false
                    section = .pending
                    expanded = []
                })
        } else {
            actions.append(
                .init(
                    title: model.isPaused ? "Resume" : "Pause",
                    symbol: model.isPaused ? "Play" : "Pause",
                    isEnabled: model.count(section: .pending, history: false) > 0
                ) {
                    dismissTools()
                    model.isPaused.toggle()
                    if section == .pending {
                        history = false
                        section = .pending
                        expanded = []
                    }
                })
        }
        if section != .completed || history {
            actions.append(
                .init(
                    title: "Clear \(section.rawValue.lowercased())",
                    symbol: "Trash", isEnabled: model.count(section: section, history: history) > 0
                ) {
                    dismissTools()
                    confirmClear = true
                })
        }
        return actions
    }

    private func dismissTools() {
        menuLevel = .closed
        viewPresented = false
        typePresented = false
    }

}

#if DEBUG
    #Preview("Downloads · empty") {
        @Previewable @State var pillOpen = false
        VStack(spacing: 0) {
            PageHeader(title: "Downloads").pillBackdrop(pillOpen)
            DownloadsView(model: DownloadsViewModel())
        }
        .onPreferenceChange(PillDropdownOpenKey.self) { pillOpen = $0 }
        .background(NavigationStyle.background)
        .preferredColorScheme(.dark)
    }

    #Preview("Downloads · active and failed") {
        @Previewable @State var pillOpen = false
        VStack(spacing: 0) {
            PageHeader(title: "Downloads").pillBackdrop(pillOpen)
            DownloadsView(
                model: DownloadsViewModel(entries: [
                    .init(
                        id: "preview-active", titleID: "preview-title", title: "Sample title",
                        chapter: "Chapter 12", status: .downloading, progress: 0.65),
                    .init(
                        id: "preview-failed", titleID: "preview-title", title: "Sample title",
                        chapter: "Chapter 13", status: .failed),
                    .init(
                        id: "preview-complete", titleID: "preview-history",
                        title: "Completed title",
                        chapter: "Chapter 1", status: .completed, bytes: 24_000_000,
                        completedAt: .now),
                ]))
        }
        .onPreferenceChange(PillDropdownOpenKey.self) { pillOpen = $0 }
        .background(NavigationStyle.background)
        .preferredColorScheme(.dark)
    }
#endif

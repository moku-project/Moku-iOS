import SwiftUI

struct LibraryControls: View {
    enum Panel { case mode, view, layout, sort, filter }
    let model: LibraryViewModel
    @AppStorage("preferences.modeTabs") private var savedModes = ""
    @Binding var mode: ContentMode
    @Binding var panel: Panel?
    @Binding var menuLevel: RadialMenuLevel
    @Binding var foldersPresented: Bool
    @Binding var layoutValue: String
    let layout: LibraryLayout
    let reduceMotion: Bool
    let selectView: (LibraryTab) -> Void
    let dismissTools: () -> Void

    var body: some View { viewControls }

    private var viewControls: some View {
        HStack(spacing: 0) {
            IconRail(
                title: model.folder?.name ?? model.tab.rawValue,
                symbol: model.folder != nil ? "FolderSimple" : viewSymbol,
                isPresented: panel == .view,
                itemCount: model.folder == nil
                    && [.saved, .downloaded, .starred].contains(model.tab) ? 3 : 4,
                reduceMotion: reduceMotion,
                toggle: { toggle(.view) }
            ) { menuContent(.view) }
            .accessibilityLabel("Library view")
            .accessibilityValue(model.folder?.name ?? model.tab.rawValue)
            .pillBackdrop(panel == .layout || panel == .mode)
            .accessibilityIdentifier("library.activeView")
            .accessibilityAction(.escape) { dismissTools() }
            .frame(maxWidth: .infinity, alignment: .leading)
            layoutToggle.pillBackdrop(panel == .view || panel == .mode)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, NavigationStyle.pagePadding).padding(.top, 4)
    }

    private var layoutToggle: some View {
        IconRail(
            title: layout.title, symbol: layout.symbol,
            isPresented: panel == .layout, itemCount: LibraryLayout.allCases.count - 1,
            reduceMotion: reduceMotion, iconOnly: true, trailing: true,
            toggle: { toggle(.layout) }
        ) { menuContent(.layout) }
        .accessibilityLabel("Library layout")
        .accessibilityValue(layout.title)
        .accessibilityIdentifier("library.layout.toggle")
        .accessibilityAction(.escape) { dismissTools() }
    }

    private var viewSymbol: String {
        switch model.tab {
        case .downloaded: "DownloadSimple"
        case .starred: "Star"
        default: "Books"
        }
    }

    @ViewBuilder private func menuContent(_ panel: Panel) -> some View {
        switch panel {
        case .sort:
            MenuSection("Order by")
            ForEach(LibrarySort.allCases) { sort in
                MenuRow(sort.rawValue, selected: model.sort == sort) {
                    model.sort = sort
                }
            }
            Divider().padding(.vertical, 4)
            MenuRow(
                model.ascending ? "Ascending" : "Descending",
                symbol: model.ascending ? "ArrowUp" : "ArrowDown"
            ) { model.ascending.toggle() }
        case .filter:
            HStack {
                Spacer()
                Button("Clear all") { model.clearFilters() }.font(
                    .system(size: 12)
                ).foregroundStyle(.secondary)
            }.padding(.horizontal, 10)
            MenuSection("Content")
            MenuRow("Unread", selected: model.unreadOnly) {
                model.unreadOnly.toggle()
            }
            MenuRow("Started", selected: model.startedOnly) {
                model.startedOnly.toggle()
            }
            Divider().padding(.vertical, 4)
            MenuSection("Status")
            ForEach(LibraryStatus.allCases) { status in
                MenuRow(status.rawValue, selected: model.status == status) {
                    model.status = model.status == status ? nil : status
                }
            }
        case .view:
            if model.folder != nil || model.tab != .saved {
                IconRailRow(title: "Saved", symbol: "Books", selected: false) {
                    selectView(.saved)
                }
            }
            if model.folder != nil || model.tab != .downloaded {
                IconRailRow(title: "Downloaded", symbol: "DownloadSimple", selected: false) {
                    selectView(.downloaded)
                }
            }
            if model.folder != nil || model.tab != .starred {
                IconRailRow(title: "Starred", symbol: "Star", selected: false) {
                    selectView(.starred)
                }
            }
            IconRailRow(title: "Folders", symbol: "FolderSimple", selected: false) {
                dismissTools()
                foldersPresented = true
            }
        case .layout:
            ForEach(LibraryLayout.allCases.filter { $0 != layout }) { choice in
                IconRailRow(
                    title: choice.title, symbol: choice.symbol, selected: false, iconOnRight: true
                ) {
                    layoutValue = choice.rawValue
                    dismissTools()
                }
                .accessibilityIdentifier("library.layout.\(choice.rawValue)")
            }
        case .mode:
            ForEach(ModeTabConfiguration(storage: savedModes).visible) { choice in
                MenuRow(
                    choice.title,
                    selected: mode == choice, fontSize: 17, iconSize: 22,
                    centered: true
                ) {
                    mode = choice
                    dismissTools()
                }
                .accessibilityIdentifier("library.mode.\(choice.rawValue)")
            }
        }
    }

    private func toggle(_ target: Panel) {
        menuLevel = .closed
        panel = panel == target ? nil : target
    }
}

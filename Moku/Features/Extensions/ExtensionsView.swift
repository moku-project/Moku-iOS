import SwiftUI

struct ExtensionsView: View {
    let search: (SourceExtension) -> Void
    private enum SectionChoice: String, CaseIterable, Identifiable {
        case installed = "Installed"
        case browse = "Browse"
        case repositories = "Repositories"
        var id: Self { self }
        var symbol: String { self == .repositories ? "FolderSimple" : "PuzzlePiece" }
    }
    private enum ToolSheet: String, Identifiable {
        case search, filters
        var id: Self { self }
    }
    @State private var section: SectionChoice = .installed
    @State private var viewPicker = false
    @State private var menuLevel: RadialMenuLevel = .closed
    @State private var toolSheet: ToolSheet?
    @State private var settingsSource: SourceExtension?
    @State private var model = ExtensionsViewModel(repository: AppDependencies.extensionRepository)
    @State private var isAdding = false
    @State private var repositoryName = ""
    @State private var repositoryURL = ""
    @State private var removing: SourceExtension?
    @State private var deleting: ExtensionRepositoryInfo?
    @State private var renaming: ExtensionRepositoryInfo?
    @State private var rename = ""
    @Environment(\.navigationContentBottomInset) private var bottomInset
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("preferences.animations") private var animations = true
    @ScaledMetric(relativeTo: .body) private var rowIconSize = 22
    @ScaledMetric(relativeTo: .body) private var logoSize = 64
    private var reduceMotion: Bool { systemReduceMotion || !animations }
    private var visibleRepositories: [ExtensionRepositoryInfo] {
        model.repositories.filter {
            model.query.isEmpty || $0.title.localizedStandardContains(model.query)
                || $0.indexUrl.localizedStandardContains(model.query)
        }
    }
    private var filterCount: Int {
        (model.repositoryID == nil ? 0 : 1) + (model.language == nil ? 0 : 1)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                ModeTabs(
                    mode: Binding(get: { model.media }, set: { model.media = $0 }),
                    prefix: "extensions", onSelect: dismissTools
                ).pillBackdrop(viewPicker).zIndex(3)
                viewControls.zIndex(2)
                content
                    .firstLoadSkeleton(
                        "extensions-\(section.rawValue)", loading: model.isLoading,
                        style: .extensions
                    )
                    .pillBackdrop(viewPicker)
                    .opacity(menuLevel == .closed ? 1 : 0.18)
                    .overlay {
                        if viewPicker || menuLevel != .closed {
                            Color.black.opacity(0.001).contentShape(Rectangle())
                                .onTapGesture { dismissTools() }
                                .accessibilityLabel("Dismiss Extensions menu")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { dismissTools() }
                        }
                    }
            }
            .overlay(alignment: .bottomTrailing) {
                RadialMenu(
                    level: $menuLevel, reduceMotion: reduceMotion,
                    actions: radialActions, accessibilityPrefix: "extensions",
                    toolsTitle: "Extensions"
                )
                .pillBackdrop(viewPicker)
                .padding(.trailing, max(16, (geometry.size.width - 336) / 2))
                .padding(.bottom, bottomInset + 12)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: viewPicker)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: menuLevel)
        }
        .background(NavigationStyle.background)
        .tint(NavigationStyle.accent)
        .overlay {
            if model.isWorking {
                ContentSkeleton(style: .extensions, count: 1).padding(24)
                    .modifier(FloatingSurface(cornerRadius: 20))
            }
        }
        .disabled(model.isWorking)
        .task(id: [
            model.query, model.repositoryID ?? "", model.language ?? "", model.media.rawValue,
        ]) {
            do {
                if !model.query.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                await model.load()
            } catch {}
        }
        .onDisappear { dismissTools() }
        .sheet(item: $toolSheet) { tool in
            ExtensionFilters(
                model: model, repositoriesOnly: section == .repositories,
                title: tool == .search ? "Search" : "Filters", close: { toolSheet = nil })
        }
        .sheet(isPresented: $isAdding) {
            AddRepositoryView(
                model: model, repositoryName: $repositoryName, repositoryURL: $repositoryURL,
                isAdding: $isAdding)
        }
        .sheet(item: $settingsSource) {
            SourceSettingsView(source: $0, repository: AppDependencies.extensionRepository)
        }
        .alert(
            "Uninstall \(removing?.displayName ?? "extension")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                if let item = removing { change(.uninstallExtension, item) }
            }
        } message: {
            Text("This source will no longer be available for search.")
        }
        .alert(
            "Remove repository?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let repo = deleting {
                    model.repositoryID = nil
                    Task {
                        await model.perform {
                            try await $0.repositoryAction(.deleteRepository, id: repo.id, name: "")
                        }
                    }
                }
            }
        } message: {
            Text(
                "This removes the repository and its extension catalog. Uninstall its sources first."
            )
        }
        .alert(
            "Rename repository",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("Name", text: $rename)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let repo = renaming {
                    let name = rename
                    Task {
                        await model.perform {
                            try await $0.repositoryAction(
                                .renameRepository, id: repo.id, name: name)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("extensions.page")
    }

    private var viewControls: some View {
        HStack(spacing: 12) {
            IconRail(
                title: section.rawValue, symbol: section.symbol,
                isPresented: viewPicker, itemCount: 2, reduceMotion: reduceMotion,
                controlIdentifier: "extensions.section", controlLabel: "Extensions view",
                toggle: {
                    menuLevel = .closed
                    viewPicker.toggle()
                }
            ) {
                ForEach(SectionChoice.allCases.filter { $0 != section }) { choice in
                    IconRailRow(title: choice.rawValue, symbol: choice.symbol, selected: false) {
                        select(choice)
                    }.accessibilityIdentifier("extensions.view.\(choice.rawValue)")
                }
            }
            Spacer(minLength: 0)
            if !model.query.isEmpty || (section != .repositories && filterCount > 0) {
                Button {
                    openTool(.filters)
                } label: {
                    Text(model.query.isEmpty ? "\(filterCount) filters" : "Search active")
                        .font(.caption).foregroundStyle(NavigationStyle.accent)
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .modifier(FloatingSurface(cornerRadius: 18))
                }.buttonStyle(.plain).accessibilityLabel("Edit search and filters")
            }
        }.padding(.horizontal, NavigationStyle.pagePadding).padding(.top, 4)
    }

    private var content: some View {
        List {
            if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("Retry") { Task { await model.load() } }.frame(minHeight: 44)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            Text(summary).font(.caption).foregroundStyle(.secondary)
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            if section == .repositories {
                if model.isLoading && model.repositories.isEmpty {
                    ContentSkeleton(style: .extensions, count: 3)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(visibleRepositories) { repo in
                    repositoryRow(repo)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canRemove(repo) {
                                Button("Delete", role: .destructive) { deleting = repo }
                            }
                        }
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                if visibleRepositories.isEmpty && !model.isLoading {
                    empty(
                        model.query.isEmpty ? "No repositories yet" : "No matching repositories",
                        detail: model.query.isEmpty
                            ? "Add a repository to browse its extensions." : "Try another name."
                    )
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                Button {
                    dismissTools()
                    isAdding = true
                } label: {
                    Text("+ Add repository").font(.subheadline.weight(.medium))
                        .foregroundStyle(NavigationStyle.accent).frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityIdentifier(
                    "extensions.AddRepositoryView(model: model, repositoryName: $repositoryName, repositoryURL: $repositoryURL, isAdding: $isAdding)"
                )
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else {
                ForEach(section == .installed ? model.visibleInstalled : model.items) { item in
                    ExtensionRow(
                        item: item, search: search, configure: { settingsSource = $0 },
                        change: change
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if item.installed {
                            Button("Uninstall", role: .destructive) { removing = item }
                        }
                    }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                if model.isLoading {
                    ContentSkeleton(style: .extensions, count: 5)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else if (section == .installed ? model.visibleInstalled : model.items).isEmpty {
                    empty(emptyTitle, detail: emptyDetail)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    if section == .installed && model.installed.isEmpty {
                        Button("Browse extensions") { select(.browse) }
                            .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.plain)
                            .foregroundStyle(NavigationStyle.accent)
                            .accessibilityIdentifier("extensions.browse")
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                }
                if section == .browse && model.items.count < model.total {
                    Button("Load more") { Task { await model.load(more: true) } }
                        .frame(maxWidth: .infinity, minHeight: 44).disabled(model.isLoading)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .listRowSpacing(8)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.top, 0, for: .scrollContent)
        .tracksNavigationScroll()
        .environment(\.navigationContentBottomInset, bottomInset + 80)
        .refreshable { await model.load() }
        .accessibilityIdentifier("extensions.list")
    }

    private var summary: String {
        switch section {
        case .installed:
            let updates = model.visibleInstalled.filter { $0.needsUpdate == true }.count
            return "\(model.visibleInstalled.count) installed"
                + (updates > 0 ? " · \(updates) updates" : "")
        case .browse: return "\(model.total.formatted()) extensions"
        case .repositories: return "\(visibleRepositories.count) repositories"
        }
    }
    private var emptyTitle: String {
        if !model.query.isEmpty || filterCount > 0 || model.media != .all {
            return "No matching extensions"
        }
        return section == .installed
            ? "Nothing here yet"
            : model.repositories.isEmpty ? "Add your first repository" : "No extensions found"
    }
    private var emptyDetail: String {
        if !model.query.isEmpty || filterCount > 0 || model.media != .all {
            return "Try another name or change your filters."
        }
        return section == .installed
            ? "Browse extensions to add your first source."
            : "Open Repositories to add or refresh an index."
    }
    private func empty(_ title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.title2.bold())
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 200)
    }

    private func repositoryRow(_ repo: ExtensionRepositoryInfo) -> some View {
        HStack(spacing: 12) {
            PhosphorIcon("FolderSimple").iconSize(logoSize * 0.65)
                .foregroundStyle(.secondary).frame(width: logoSize, height: logoSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(repo.title).font(.body.weight(.medium)).lineLimit(2)
                Text(repo.indexUrl).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if !canRemove(repo) {
                    Text("Uninstall its sources before removing").font(.caption2).foregroundStyle(
                        .secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            OverflowMenu {
                Button("Refresh") {
                    Task {
                        await model.perform {
                            try await $0.repositoryAction(.syncRepository, id: repo.id, name: "")
                        }
                    }
                }
                Button("Edit name") {
                    rename = repo.title
                    renaming = repo
                }
            } label: {
                PhosphorIcon("DotsThree").iconSize(rowIconSize)
                    .foregroundStyle(.secondary).frame(width: 44, height: 44)
            }.accessibilityLabel("Manage \(repo.title)")
        }.padding(.vertical, 4)
    }
    private func canRemove(_ repo: ExtensionRepositoryInfo) -> Bool {
        model.installedLoaded && !model.installed.contains { $0.repositoryId == repo.id }
    }
    private var radialActions: [RadialAction] {
        guard menuLevel != .closed else { return [] }
        return [
            .init(title: "Search", symbol: "MagnifyingGlass") { openTool(.search) },
            .init(title: "Filter", symbol: "Funnel", isEnabled: section != .repositories) {
                openTool(.filters)
            },
            .init(title: "Repositories", symbol: "FolderSimple") { select(.repositories) },
            .init(title: "Add", symbol: "Plus") {
                dismissTools()
                isAdding = true
            },
        ]
    }
    private func dismissTools() {
        viewPicker = false
        menuLevel = .closed
    }
    private func select(_ choice: SectionChoice) {
        section = choice
        dismissTools()
    }
    private func openTool(_ tool: ToolSheet) {
        dismissTools()
        toolSheet = tool
    }

    private func change(_ action: ExtensionAction, _ item: SourceExtension) {
        Task {
            await model.perform { try await $0.extensionAction(action, package: item.packageName) }
        }
    }
}

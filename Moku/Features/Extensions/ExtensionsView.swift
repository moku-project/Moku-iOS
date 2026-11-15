import SwiftUI

struct ExtensionsView: View {
    let search: (SourceExtension) -> Void
    private enum SectionChoice: String, CaseIterable, Identifiable {
        case installed = "Installed"
        case browse = "Browse"
        case repositories = "Repositories"
        var id: Self { self }
    }
    @State private var section: SectionChoice = .installed
    @State private var settingsSource: SourceExtension?
    @State private var librarySource: SourceExtension?
    @State private var model = ExtensionsViewModel(repository: AppDependencies.extensionRepository)
    @State private var isAdding = false
    @State private var repositoryName = ""
    @State private var repositoryURL = ""
    @State private var removing: SourceExtension?
    @State private var deleting: ExtensionRepositoryInfo?
    @State private var renaming: ExtensionRepositoryInfo?
    @State private var rename = ""
    @State private var installingURL = false
    @State private var externalURL = ""
    @AppStorage("preferences.modeTabs") private var savedModes = ""
    private var modes: [ContentMode] { ModeTabConfiguration(storage: savedModes).visible }
    private var updatable: [SourceExtension] { model.visibleInstalled.filter { $0.needsUpdate == true } }
    private var upToDate: [SourceExtension] { model.visibleInstalled.filter { $0.needsUpdate != true } }
    private var visibleRepositories: [ExtensionRepositoryInfo] {
        model.repositories.filter {
            model.query.isEmpty || $0.title.localizedStandardContains(model.query)
                || $0.indexUrl.localizedStandardContains(model.query)
        }
    }
    private var filterCount: Int {
        (model.repositoryID == nil ? 0 : 1) + (model.language == nil ? 0 : 1) + (model.media == .all ? 0 : 1)
    }

    var body: some View {
        Group {
            List {
                Section {
                    Picker("View", selection: $section) {
                        ForEach(SectionChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("extensions.section")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listSectionSpacing(.compact)
                if let error = model.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Retry") { Task { await model.load() } }
                    }
                }
                switch section {
                case .installed: installedSections
                case .browse: browseSections
                case .repositories: repositorySections
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .firstLoadSkeleton(
                "extensions-\(section.rawValue)", loading: model.isLoading, style: .extensions)
            .refreshable { await model.load() }
            .accessibilityIdentifier("extensions.list")
        }
        .background(NavigationStyle.background.ignoresSafeArea())
        .searchable(
            text: $model.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: section == .repositories ? "Find Repositories" : "Find Extensions")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                filterMenu
                Menu {
                    Button("Add Repository…", systemImage: "folder.badge.plus") { isAdding = true }
                    Button("Install from URL…", systemImage: "link") {
                        externalURL = ""
                        installingURL = true
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                } primaryAction: {
                    isAdding = true
                }
                .accessibilityIdentifier("extensions.addRepository")
            }
        }
        .overlay {
            if model.isWorking {
                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .disabled(model.isWorking)
        .task(id: [
            model.query, model.repositoryID ?? "", model.language ?? "", model.media.rawValue,
        ]) {
            do {
                if !model.query.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                await model.load(refreshSections: !model.installedLoaded)
            } catch {}
        }
        .sheet(isPresented: $isAdding) {
            AddRepositoryView(
                model: model, repositoryName: $repositoryName, repositoryURL: $repositoryURL,
                isAdding: $isAdding)
        }
        .sheet(item: $settingsSource) {
            SourceSettingsView(source: $0, repository: AppDependencies.extensionRepository)
        }
        .sheet(item: $librarySource) { ExtensionLibrarySheet(source: $0) }
        .confirmationDialog(
            "Uninstall \(removing?.displayName ?? "extension")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible, presenting: removing
        ) { item in
            Button("Uninstall", role: .destructive) { change(.uninstallExtension, item) }
        } message: { _ in
            Text("This source will no longer be available for search.")
        }
        .confirmationDialog(
            "Remove \(deleting?.title ?? "repository")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible, presenting: deleting
        ) { repo in
            Button("Remove Repository", role: .destructive) {
                model.repositoryID = nil
                Task {
                    await model.perform {
                        try await $0.repositoryAction(.deleteRepository, id: repo.id, name: "")
                    }
                }
            }
        } message: { _ in
            Text("This removes the repository and its extension catalog.")
        }
        .alert(
            "Rename Repository",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("Name", text: $rename)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let repo = renaming {
                    let name = rename
                    Task {
                        await model.perform {
                            try await $0.repositoryAction(.renameRepository, id: repo.id, name: name)
                        }
                    }
                }
            }
        }
        .alert("Install from URL", isPresented: $installingURL) {
            TextField("https://…/extension.apk", text: $externalURL)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Button("Cancel", role: .cancel) {}
            Button("Install") {
                let url = externalURL.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    if await model.perform({ try await $0.installExternal(url: url) }) {
                        Toaster.shared.show("Extension installed")
                    }
                }
            }
        } message: {
            Text("Only install extensions from sources you trust. They run on this device with network access.")
        }
        .sheet(item: $verification) { SourceVerificationView(request: $0) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("extensions.page")
    }

    // MARK: Toolbar

    private var filterMenu: some View {
        Menu {
            Picker("Content", selection: $model.media) {
                ForEach(modes) { Text($0.title).tag($0) }
            }
            if section != .repositories {
                Picker(selection: $model.repositoryID) {
                    Text("All Repositories").tag(String?.none)
                    ForEach(model.repositories) { repo in
                        Text(repo.title).tag(Optional(repo.id))
                    }
                } label: {
                    Label("Repository", systemImage: "folder")
                }
                .pickerStyle(.menu)
                Picker(selection: $model.language) {
                    Text("All Languages").tag(String?.none)
                    ForEach(model.languages, id: \.self) { language in
                        Text(Locale.current.localizedString(forLanguageCode: language) ?? language)
                            .tag(Optional(language))
                    }
                } label: {
                    Label("Language", systemImage: "globe")
                }
                .pickerStyle(.menu)
            }
            if filterCount > 0 {
                Divider()
                Button("Reset Filters", systemImage: "arrow.counterclockwise") {
                    model.repositoryID = nil
                    model.language = nil
                    model.media = .all
                }
            }
        } label: {
            Label(
                "Filters",
                systemImage: filterCount > 0
                    ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("extensions.filters")
    }

    // MARK: Sections

    @ViewBuilder private var installedSections: some View {
        if !updatable.isEmpty {
            Section {
                ForEach(updatable) { row($0) }
            } header: {
                HStack {
                    Text("Updates")
                    Spacer()
                    Button("Update All", action: updateAll)
                        .font(.subheadline).textCase(nil)
                }
            }
        }
        if !upToDate.isEmpty {
            Section {
                ForEach(upToDate) { row($0) }
            } header: {
                Text("Installed")
            } footer: {
                Text("\(model.visibleInstalled.count) installed. Tap a source to browse it; touch and hold for settings and migration.")
            }
        }
        if !model.isLoading && model.visibleInstalled.isEmpty {
            emptyState
        }
    }

    @ViewBuilder private var browseSections: some View {
        if !model.items.isEmpty {
            Section {
                ForEach(model.items) { row($0) }
                if model.items.count < model.total {
                    Button("Load More") { Task { await model.load(more: true) } }
                        .disabled(model.isLoading)
                }
            } header: {
                Text("\(model.total.formatted()) extensions")
            }
        } else if !model.isLoading {
            emptyState
        }
    }

    @ViewBuilder private var repositorySections: some View {
        Section {
            ForEach(visibleRepositories) { repositoryRow($0) }
            Button {
                isAdding = true
            } label: {
                Label("Add Repository", systemImage: "plus")
            }
            .accessibilityIdentifier("extensions.addRepository.row")
        } header: {
            Text("\(visibleRepositories.count) repositories")
        } footer: {
            Text("Tap a repository to browse its extensions. A repository can be removed once its sources are uninstalled.")
        }
    }

    @ViewBuilder private var emptyState: some View {
        Section {
            if !model.query.isEmpty {
                ContentUnavailableView.search(text: model.query)
            } else if filterCount > 0 {
                ContentUnavailableView(
                    "No Matching Extensions", systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Change your filters to see more."))
            } else if section == .installed {
                ContentUnavailableView {
                    Label("No Extensions Installed", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("Browse extensions to add your first source.")
                } actions: {
                    Button("Browse Extensions") { section = .browse }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("extensions.browse")
                }
            } else {
                ContentUnavailableView {
                    Label(
                        model.repositories.isEmpty ? "Add Your First Repository" : "No Extensions Found",
                        systemImage: "folder")
                } description: {
                    Text("Repositories list the extensions you can install.")
                } actions: {
                    Button("Add Repository") { isAdding = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .listRowBackground(Color.clear)
    }

    private func row(_ item: SourceExtension) -> some View {
        ExtensionRow(
            item: item, search: search, configure: { settingsSource = $0 },
            openLibrary: { librarySource = $0 },
            verify: { verifySource($0) },
            uninstall: { removing = $0 },
            change: change)
    }

    @Environment(\.presentSourceVerification) private var presentSourceVerification
    /// Used when no `.sourceVerificationHost()` is installed above this page.
    @State private var verification: SourceVerificationRequest?

    private func verifySource(_ item: SourceExtension) {
        if presentSourceVerification.isAvailable {
            presentSourceVerification(extensionID: item.packageName, url: nil, sourceName: item.displayName)
        } else {
            verification = SourceVerificationRequest(
                extensionID: item.packageName, url: nil, sourceName: item.displayName)
        }
    }

    private func repositoryRow(_ repo: ExtensionRepositoryInfo) -> some View {
        Button {
            model.repositoryID = repo.id
            section = .browse
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder").font(.title3).foregroundStyle(NavigationStyle.accent)
                    .frame(width: 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.title).foregroundStyle(.primary).lineLimit(2)
                    Text(repo.indexUrl).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canRemove(repo) {
                Button("Remove", role: .destructive) { deleting = repo }
            }
            Button("Refresh") { refresh(repo) }.tint(NavigationStyle.accent)
        }
        .contextMenu {
            Button("Browse Extensions", systemImage: "puzzlepiece.extension") {
                model.repositoryID = repo.id
                section = .browse
            }
            Button("Refresh", systemImage: "arrow.clockwise") { refresh(repo) }
            Button("Rename", systemImage: "pencil") {
                rename = repo.title
                renaming = repo
            }
            Button("Copy Index URL", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = repo.indexUrl
            }
            Divider()
            Button("Remove", systemImage: "trash", role: .destructive) { deleting = repo }
                .disabled(!canRemove(repo))
        }
        .accessibilityHint(canRemove(repo) ? "" : "Uninstall its sources before removing")
    }

    // MARK: Actions

    private func canRemove(_ repo: ExtensionRepositoryInfo) -> Bool {
        model.installedLoaded && !model.installed.contains { $0.repositoryId == repo.id }
    }

    private func refresh(_ repo: ExtensionRepositoryInfo) {
        Task {
            await model.perform {
                try await $0.repositoryAction(.syncRepository, id: repo.id, name: "")
            }
        }
    }

    private func updateAll() {
        let packages = model.installed.filter { $0.needsUpdate == true }.map(\.packageName)
        Task {
            if await model.perform({ repository in
                for package in packages { try await repository.extensionAction(.updateExtension, package: package) }
            }) {
                Toaster.shared.show(packages.count == 1 ? "Extension updated" : "\(packages.count) extensions updated")
            }
        }
    }

    private func change(_ action: ExtensionAction, _ item: SourceExtension) {
        Task {
            await model.perform { try await $0.extensionAction(action, package: item.packageName) }
        }
    }
}

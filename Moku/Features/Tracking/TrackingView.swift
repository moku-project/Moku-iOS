import AuthenticationServices
import SwiftUI

struct TrackingView: View {
    /// The Settings → Tracker Accounts page: accounts first, import as a secondary action.
    var settingsPage = false
    @Environment(AppDataStore.self) private var appData
    @Environment(LibraryStore.self) private var library
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var model = TrackingViewModel.makeDefault()
    /// Account details, or the token-paste fallback for a service not yet connected.
    @State private var account: TrackingService?
    /// In-app authorization page for a service.
    @State private var signIn: TrackingService?
    @State private var disconnecting: TrackingService?
    @State private var choosingImport = false
    @State private var importing = false
    @State private var importStep: ImportStep = .setup
    @State private var confirmDiscard = false
    @State private var token = ""
    /// The service whose authorization page was opened in Safari; polled until connected.
    @State private var waitingFor: String?
    @State private var dryRun = false
    @State private var matchingID: String?
    @State private var matchQuery = ""
    @State private var matches: [MediaEntry] = []
    @State private var searching = false
    private enum ImportStep { case setup, review }

    private var connected: [TrackingService] { model.services.filter { $0.isLoggedIn && !$0.comingSoon } }

    var body: some View {
        List {
            servicesSection
            importSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NavigationStyle.background.ignoresSafeArea())
        .firstLoadSkeleton("tracking", loading: model.loading, style: .extensions)
        .refreshable { await model.load() }
        .accessibilityIdentifier("tracking.scroll")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Import List…", systemImage: "square.and.arrow.down") { startImport() }
                        .disabled(connected.isEmpty)
                        .accessibilityIdentifier("tracking.action.Import list")
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.load() } }
                        .disabled(model.loading)
                } label: {
                    Label("Tracking Actions", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("tracking.fab")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tracking.page")
        .task {
            await model.configure(directory: appData.directory)
            await model.load()
        }
        .task(id: waitingFor) {
            guard let key = waitingFor else { return }
            for _ in 0..<48 {
                do { try await Task.sleep(for: .milliseconds(2500)) } catch { return }
                guard waitingFor == key else { return }
                await model.load()
                if model.services.first(where: { $0.id == key })?.isLoggedIn == true {
                    waitingFor = nil
                    token = ""
                    account = nil
                    return
                }
            }
            waitingFor = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && waitingFor != nil { Task { await model.load() } }
        }
        .onDisappear {
            waitingFor = nil
            token = ""
            model.stopRequested = true
        }
        .modifier(NoticeAlert(model: model, active: account == nil && signIn == nil && !importing))
        .confirmationDialog(
            "Disconnect \(disconnecting?.name ?? "service")?",
            isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }),
            titleVisibility: .visible, presenting: disconnecting
        ) { service in
            Button("Disconnect", role: .destructive) {
                Task {
                    if await model.disconnect(service) { account = nil }
                }
            }
        } message: { _ in
            Text("Your saved titles will be kept.")
        }
        .confirmationDialog("Import From", isPresented: $choosingImport, titleVisibility: .visible) {
            ForEach(connected) { tracker in
                Button(tracker.name) { chooseImport(tracker) }
            }
        }
        .sheet(item: $account, onDismiss: {
            waitingFor = nil
            token = ""
        }) { service in
            accountSheet(service)
        }
        .sheet(item: $signIn) { service in
            if let url = authURL(service) {
                TrackerSignInSheet(service: service, url: url) { value in
                    let success = await model.connect(service, token: value)
                    if !success { model.notice = nil }
                    return success
                }
            }
        }
        .sheet(isPresented: $importing, onDismiss: closeImport) {
            importSheet
        }
    }

    // MARK: Sections

    private var servicesSection: some View {
        Section {
            if model.loading && model.services.isEmpty {
                LabeledContent("Tracking services") { ProgressView() }
            }
            ForEach(model.services) { tracker in
                serviceRow(tracker)
            }
            if !model.loading && model.services.isEmpty {
                ContentUnavailableView {
                    Label("No Services Available", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Tracking services couldn’t be loaded.")
                } actions: {
                    Button("Try Again") { Task { await model.load() } }
                }
            }
        } header: {
            Text("Services")
        } footer: {
            if !model.services.isEmpty {
                Text("\(connected.count) connected. Sign in to import your lists and keep progress in sync.")
            }
        }
    }

    @ViewBuilder private var importSection: some View {
        if !connected.isEmpty || !model.items.isEmpty {
            Section {
                if !model.items.isEmpty {
                    Button {
                        if let tracker = model.services.first(where: { $0.key == model.trackerKey }) {
                            chooseImport(tracker)
                        } else {
                            importStep = .review
                            importing = true
                        }
                    } label: {
                        LabeledContent("Continue Saved Import", value: "\(model.items.count) titles")
                    }
                }
                Button("Import List…") { startImport() }
                    .disabled(connected.isEmpty)
            } header: {
                Text("Import")
            } footer: {
                Text("Add titles from your tracker lists to your library.")
            }
        }
    }

    private func serviceRow(_ tracker: TrackingService) -> some View {
        Button {
            guard !tracker.comingSoon else { return }
            if tracker.isLoggedIn { account = tracker } else { connect(tracker) }
        } label: {
            HStack(spacing: 14) {
                TrackerBrandIcon(service: tracker).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tracker.name).foregroundStyle(.primary)
                    Text(tracker.isLoggedIn ? (tracker.username.map { "Signed in as \($0)" } ?? "Connected") : tracker.status)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if !tracker.comingSoon {
                    Text(tracker.isLoggedIn ? "Manage" : "Connect")
                        .foregroundStyle(tracker.isLoggedIn ? Color.secondary : NavigationStyle.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(tracker.comingSoon)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if tracker.isLoggedIn {
                Button("Disconnect", role: .destructive) { disconnecting = tracker }
            }
        }
        .contextMenu {
            if !tracker.comingSoon {
                if tracker.isLoggedIn {
                    Button("Import List…", systemImage: "square.and.arrow.down") { chooseImport(tracker) }
                    Button("Account", systemImage: "person.crop.circle") { account = tracker }
                    Button("Disconnect", systemImage: "xmark.circle", role: .destructive) { disconnecting = tracker }
                } else {
                    Button("Sign In", systemImage: "person.crop.circle.badge.plus") { connect(tracker) }
                    Button("Use a Token", systemImage: "key") {
                        token = ""
                        account = tracker
                    }
                }
            }
        }
        .accessibilityLabel("\(tracker.name), \(tracker.status)")
        .accessibilityIdentifier("tracking.service.\(tracker.key)")
    }

    // MARK: Sign in

    private func authURL(_ service: TrackingService) -> URL? {
        service.authUrl.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }

    /// Opens the tracker's sign-in. Falls back to the token sheet when there is no authorization page.
    private func connect(_ tracker: TrackingService) {
        token = ""
        guard let url = authURL(tracker) else {
            account = tracker
            return
        }
        if let scheme = TrackerSignIn.callbackScheme(for: url) {
            Task {
                do {
                    let callback = try await webAuthenticationSession.authenticate(
                        using: url, callbackURLScheme: scheme, preferredBrowserSession: .ephemeral)
                    _ = await model.connect(tracker, token: callback.absoluteString)
                } catch ASWebAuthenticationSessionError.canceledLogin {
                } catch {
                    model.notice = "Couldn’t sign in to \(tracker.name). Try again, or paste a token."
                }
            }
        } else {
            signIn = tracker
        }
    }

    private func accountSheet(_ service: TrackingService) -> some View {
        NavigationStack {
            Form {
                // Show the latest state of this service (it may connect while the sheet is open).
                let current = model.services.first { $0.id == service.id } ?? service
                Section {
                    HStack(spacing: 14) {
                        TrackerBrandIcon(service: current).frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.name).font(.headline)
                            Text(current.status).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                if current.isLoggedIn {
                    Section {
                        LabeledContent("Signed in as", value: current.username ?? "Connected")
                        Button("Import List…") {
                            account = nil
                            chooseImport(current)
                        }
                    }
                    Section {
                        Button("Disconnect", role: .destructive) { disconnecting = current }
                    }
                } else {
                    if let url = authURL(current) {
                        Section {
                            Button("Sign In to \(current.name)") {
                                account = nil
                                connect(current)
                            }
                        } footer: {
                            Text("Opens \(current.name)’s sign-in page here and connects when you approve access.")
                        }
                        Section {
                            Button(waitingFor == current.id ? "Stop Waiting" : "Open in Safari") {
                                if waitingFor == current.id {
                                    waitingFor = nil
                                } else {
                                    openURL(url)
                                    waitingFor = current.id
                                }
                            }
                            Button("Copy Authorization Link") {
                                UIPasteboard.general.string = url.absoluteString
                                Toaster.shared.show("Link copied")
                            }
                        } header: {
                            Text("Sign in elsewhere")
                        } footer: {
                            Text("Approve access in your browser, then paste the token or the redirected URL below.")
                        }
                    }
                    Section {
                        SecureField("Token or redirect URL", text: $token)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("tracking.token")
                        if model.working {
                            LabeledContent("Connecting…") { ProgressView() }
                        }
                    } header: {
                        Text("Token")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle(service.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(service.isLoggedIn ? "Done" : "Cancel") { account = nil }
                        .disabled(model.working)
                }
                if !(model.services.first { $0.id == service.id } ?? service).isLoggedIn {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Connect") {
                            Task { if await model.connect(service, token: token) { account = nil } }
                        }
                        .disabled(model.working || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(model.working)
            .modifier(NoticeAlert(model: model, active: true))
        }
        .presentationDetents(service.isLoggedIn ? [.medium, .large] : [.large])
    }

    // MARK: Import

    private func startImport() {
        if connected.count == 1, let tracker = connected.first {
            chooseImport(tracker)
        } else if !connected.isEmpty {
            choosingImport = true
        }
    }

    private func chooseImport(_ tracker: TrackingService) {
        model.trackerKey = tracker.key
        importStep = model.items.isEmpty ? .setup : .review
        importing = true
        Task { await model.loadSources() }
    }

    private func closeImport() {
        if model.working { model.stopRequested = true }
        matchingID = nil
        model.persist()
    }

    private var importService: String {
        model.services.first { $0.key == model.trackerKey }?.name ?? "AniList"
    }

    private var importSheet: some View {
        NavigationStack {
            Form {
                switch importStep {
                case .setup: ImportSetup(model: model)
                case .review:
                    ImportReview(
                        model: model, dryRun: $dryRun,
                        chooseMatch: { item in
                            matchQuery = item.remote.title
                            matches = []
                            matchingID = item.id
                            Task { await searchMatches() }
                        },
                        discard: { confirmDiscard = true })
                }
            }
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle(importStep == .setup ? "Import from \(importService)" : "Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { importToolbar }
            .navigationDestination(
                isPresented: Binding(get: { matchingID != nil }, set: { if !$0 { matchingID = nil } })
            ) {
                matchPage
            }
            .confirmationDialog("Discard import?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    model.discard()
                    importStep = .setup
                }
            } message: {
                Text("Imported titles will be kept. Unfinished matches will be removed.")
            }
            .modifier(NoticeAlert(model: model, active: true))
        }
        .interactiveDismissDisabled(model.working)
    }

    @ToolbarContentBuilder private var importToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if importStep == .review && model.working {
                Button(model.stopRequested ? "Stopping…" : "Stop") { model.stopRequested = true }
                    .disabled(model.stopRequested)
            } else {
                Button(importStep == .review ? "Save & Close" : "Cancel") { importing = false }
                    .disabled(model.working)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            switch importStep {
            case .setup:
                Button("Continue") {
                    Task {
                        if await model.fetchList(library: library) {
                            importStep = .review
                            await model.matchPending(library: library)
                        }
                    }
                }
                .disabled(model.working || model.statuses.isEmpty)
            case .review:
                if model.items.contains(where: { $0.state == .pending }) {
                    Button("Resume") { Task { await model.matchPending(library: library) } }
                        .disabled(model.working)
                } else {
                    Button(dryRun ? "Preview" : "Import \(model.importable.count)") {
                        Task { await model.runImport(library: library, dryRun: dryRun) }
                    }
                    .disabled(model.working || model.importable.isEmpty)
                }
            }
        }
    }

    private var matchPage: some View {
        List {
            if searching {
                LabeledContent("Searching…") { ProgressView() }
            } else if matches.isEmpty {
                ContentUnavailableView.search(text: matchQuery)
            }
            ForEach(matches) { entry in
                Button {
                    if let matchingID { model.assign(entry, to: matchingID, library: library) }
                    matchingID = nil
                } label: {
                    HStack(spacing: 12) {
                        CoverImage(url: entry.coverURL, symbol: "BookOpen")
                            .frame(width: 40, height: 56).clipShape(RoundedRectangle(cornerRadius: 5))
                        Text(entry.title).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(NavigationStyle.background.ignoresSafeArea())
        .navigationTitle("Choose Match")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $matchQuery, placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search source")
        .onSubmit(of: .search) { Task { await searchMatches() } }
    }

    private func searchMatches() async {
        guard !searching, !matchQuery.isEmpty else { return }
        searching = true
        defer { searching = false }
        do { matches = try await model.candidates(query: matchQuery) } catch {
            model.notice = "Couldn’t search this source. Try again."
        }
    }
}

/// The view model's notice, shown by whichever view is frontmost.
private struct NoticeAlert: ViewModifier {
    let model: TrackingViewModel
    let active: Bool
    func body(content: Content) -> some View {
        content.alert(
            "Tracking",
            isPresented: Binding(
                get: { active && model.notice != nil }, set: { if !$0 { model.notice = nil } })
        ) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
    }
}

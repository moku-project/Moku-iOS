import SwiftUI

struct TrackingView: View {
    var settingsPage = false
    @Environment(AppDataStore.self) private var appData
    @Environment(LibraryStore.self) private var library
    @Environment(\.openURL) private var openURL
    @Environment(\.navigationContentBottomInset) private var bottomInset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TrackingViewModel.makeDefault()
    @State private var menuLevel: RadialMenuLevel = .closed
    @State private var popup: TrackingPopup?
    @State private var service: TrackingService?
    @State private var token = ""
    @State private var waiting = false
    @State private var dryRun = false
    @State private var matchingID: String?
    @State private var matchQuery = ""
    @State private var matches: [MediaEntry] = []
    @State private var searching = false
    private enum TrackingPopup { case account, disconnect, services, setup, review, match, discard }

    var body: some View {
        Group {
            if settingsPage { settingsContent } else { mainContent }
        }
        .background(NavigationStyle.background)
        .blur(radius: popup == nil ? 0 : 4).allowsHitTesting(popup == nil).accessibilityHidden(
            popup != nil
        )
        .overlay { if let popup { popupView(popup) } }
        .preference(key: ModalPresentedKey.self, value: popup != nil)
        .buttonStyle(.plain).tint(NavigationStyle.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tracking.page")
        .task {
            await model.configure(directory: appData.directory)
            await model.load()
        }
        .task(id: waiting) {
            guard waiting else { return }
            for _ in 0..<48 {
                do { try await Task.sleep(for: .milliseconds(2500)) } catch { return }
                guard waiting else { return }
                await model.load()
                if model.services.first(where: { $0.id == service?.id })?.isLoggedIn == true {
                    waiting = false
                    token = ""
                    popup = nil
                    return
                }
            }
            waiting = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && waiting { Task { await model.load() } }
        }
        .onDisappear {
            waiting = false
            token = ""
            menuLevel = .closed
            model.stopRequested = true
        }
        .alert(
            "Tracking",
            isPresented: Binding(
                get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
        ) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
    }

    private var mainContent: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 24) {
                Label("Services", phosphor: "Broadcast").font(.body.weight(.medium))
                    .frame(minHeight: 44).padding(.horizontal, NavigationStyle.pagePadding + 12)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        if model.loading && model.services.isEmpty {
                            ContentSkeleton(style: .extensions)
                        } else {
                            Text(
                                "\(model.services.filter { $0.isLoggedIn && !$0.comingSoon }.count) connected"
                            )
                            .font(.subheadline).foregroundStyle(.secondary)
                            ForEach(model.services) { tracker in serviceRow(tracker) }
                            if model.services.isEmpty {
                                Text("No services available").font(.body).foregroundStyle(
                                    .secondary)
                                Button("Try again") { Task { await model.load() } }
                            }
                        }
                    }.padding(.horizontal, NavigationStyle.pagePadding + 12)
                        .padding(.top, 8).padding(.bottom, 16)
                        .frame(maxWidth: 700).frame(maxWidth: .infinity)
                }.firstLoadSkeleton("tracking", loading: model.loading, style: .extensions)
                    .tracksNavigationScroll().refreshable { await model.load() }
                    .accessibilityIdentifier("tracking.scroll")
                    .opacity(menuLevel == .closed ? 1 : 0.18)
                    .overlay {
                        if menuLevel != .closed {
                            Color.black.opacity(0.001).contentShape(Rectangle()).onTapGesture {
                                menuLevel = .closed
                            }
                        }
                    }
            }
            .overlay(alignment: .bottomTrailing) {
                RadialMenu(
                    level: $menuLevel, reduceMotion: reduceMotion, actions: actions,
                    accessibilityPrefix: "tracking", toolsTitle: "Tracking"
                )
                .padding(.trailing, max(16, (geometry.size.width - 336) / 2))
                .padding(.bottom, bottomInset + 12)
            }
        }
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GeneralSection("Services") {
                    if model.loading && model.services.isEmpty {
                        GeneralRow("Tracking services", detail: "Loading…") { ProgressView() }
                    }
                    ForEach(model.services) { tracker in
                        GeneralRow(tracker.name, detail: tracker.status) {
                            if !tracker.comingSoon {
                                OverflowMenu {
                                    if tracker.isLoggedIn {
                                        Button("Import list") { chooseImport(tracker) }
                                        Button("Account") {
                                            service = tracker
                                            popup = .account
                                        }
                                        Button("Disconnect", role: .destructive) {
                                            service = tracker
                                            popup = .disconnect
                                        }
                                    } else {
                                        Button("Connect") {
                                            service = tracker
                                            token = ""
                                            popup = .account
                                        }
                                    }
                                } label: {
                                    Text(tracker.isLoggedIn ? "Manage" : "Connect")
                                        .font(.system(size: 14)).foregroundStyle(GeneralStyle.text)
                                        .frame(minHeight: 44)
                                }.accessibilityLabel("Actions for \(tracker.name)")
                            }
                        }.accessibilityIdentifier("tracking.service.\(tracker.key)")
                        if tracker.id != model.services.last?.id { GeneralStyle.divider }
                    }
                    if !model.loading && model.services.isEmpty {
                        GeneralRow("Tracking services", detail: "No services available.") {
                            Button("Retry") { Task { await model.load() } }.buttonStyle(
                                GeneralTextButtonStyle())
                        }
                    }
                }
                GeneralSection("Sync") {
                    GeneralRow("Account status", detail: "Update connected services.") {
                        Button("Refresh") { Task { await model.load() } }.buttonStyle(
                            GeneralTextButtonStyle()
                        )
                        .disabled(model.loading)
                    }
                    if !model.items.isEmpty {
                        GeneralStyle.divider
                        GeneralRow("Saved import", detail: "Continue reviewing your list.") {
                            Button("Review") { popup = .review }.buttonStyle(
                                GeneralTextButtonStyle())
                        }
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.tracksNavigationScroll().accessibilityIdentifier("tracking.scroll")
    }

    private func serviceRow(_ tracker: TrackingService) -> some View {
        HStack(spacing: 18) {
            TrackerBrandIcon(service: tracker).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(tracker.name).font(.body.weight(.medium))
                Text(tracker.status).font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !tracker.comingSoon {
                OverflowMenu {
                    if tracker.isLoggedIn {
                        Button("Import list") { chooseImport(tracker) }
                        Button("Account") {
                            service = tracker
                            popup = .account
                        }
                        Button("Disconnect", role: .destructive) {
                            service = tracker
                            popup = .disconnect
                        }
                    } else {
                        Button("Connect") {
                            service = tracker
                            token = ""
                            popup = .account
                        }
                    }
                } label: {
                    PhosphorIcon("DotsThree").iconSize(22).foregroundStyle(NavigationStyle.accent)
                        .frame(width: 44, height: 44)
                }.accessibilityLabel("Actions for \(tracker.name)")
            }
        }.frame(minHeight: 84).accessibilityElement(children: .contain).accessibilityIdentifier(
            "tracking.service.\(tracker.key)")
    }
    private var actions: [RadialAction] {
        [
            .init(
                title: "Import list", symbol: "TrayArrowDown",
                isEnabled: model.services.contains { $0.isLoggedIn && !$0.comingSoon }
            ) {
                menuLevel = .closed
                let connected = model.services.filter { $0.isLoggedIn && !$0.comingSoon }
                if connected.count == 1, let tracker = connected.first {
                    chooseImport(tracker)
                } else {
                    popup = .services
                }
            },
            .init(title: "Refresh", symbol: "ArrowsClockwise", isEnabled: !model.loading) {
                menuLevel = .closed
                Task { await model.load() }
            },
        ]
    }
    private func chooseImport(_ tracker: TrackingService) {
        service = tracker
        model.trackerKey = tracker.key
        popup = model.items.isEmpty ? .setup : .review
        Task { await model.loadSources() }
    }
    private func close() {
        guard !model.working else {
            model.stopRequested = true
            return
        }
        waiting = false
        token = ""
        model.persist()
        popup = nil
    }
    private func title(_ popup: TrackingPopup) -> String {
        switch popup {
        case .account: service?.name ?? "Account"
        case .disconnect: "Disconnect \(service?.name ?? "service")?"
        case .services: "Import list"
        case .setup: "Import from \(service?.name ?? "AniList")"
        case .review: "Review import"
        case .match: "Choose match"
        case .discard: "Discard import?"
        }
    }
    private func popupView(_ current: TrackingPopup) -> some View {
        Popup(
            title: title(current), close: close,
            preferredHeight: current == .disconnect || current == .discard
                ? 240 : current == .account ? 380 : 600
        ) {
            VStack(alignment: .leading, spacing: 22) {
                switch current {
                case .account: accountContent
                case .disconnect:
                    Text("Your saved titles will be kept.").foregroundStyle(.secondary)
                case .services:
                    ForEach(model.services.filter { $0.isLoggedIn && !$0.comingSoon }) { tracker in
                        Button(tracker.name) { chooseImport(tracker) }.frame(minHeight: 44)
                    }
                case .setup: ImportSetup(model: model)
                case .review:
                    ImportReview(
                        model: model, dryRun: $dryRun,
                        chooseMatch: { item in
                            matchingID = item.id
                            matchQuery = item.remote.title
                            matches = []
                            popup = .match
                            Task { await searchMatches() }
                        }, discard: { popup = .discard })
                case .match: matchContent
                case .discard:
                    Text("Imported titles will be kept. Unfinished matches will be removed.")
                        .foregroundStyle(
                            .secondary)
                }
            }
        } actions: {
            popupActions(current)
        }
    }

    @ViewBuilder private var accountContent: some View {
        if let service {
            if service.isLoggedIn {
                Text(service.username.map { "Signed in as \($0)" } ?? "Connected")
                Button("Import list") { chooseImport(service) }.frame(minHeight: 44)
            } else {
                if let url = service.authUrl.flatMap(URL.init(string:)), url.scheme == "https" {
                    Button(waiting ? "Cancel waiting" : "Authorize \(service.name)") {
                        if waiting {
                            waiting = false
                        } else {
                            openURL(url)
                            waiting = true
                        }
                    }.frame(minHeight: 44).foregroundStyle(NavigationStyle.accent)
                    Button("Copy authorization link") {
                        UIPasteboard.general.string = url.absoluteString
                    }
                    .frame(minHeight: 44)
                }
                Text("Approve access, then paste the token or redirected URL.")
                    .font(.subheadline).foregroundStyle(.secondary)
                SecureField("Token or redirect URL", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(14).background(
                        NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 12)
                    )
                    .accessibilityIdentifier("tracking.token")
                if model.working { ProgressView().frame(maxWidth: .infinity) }
            }
        }
    }
    private var matchContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("Search source", text: $matchQuery).textInputAutocapitalization(.never)
                .autocorrectionDisabled().submitLabel(.search).onSubmit {
                    Task { await searchMatches() }
                }
                .padding(14).background(
                    NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            Button("Search") { Task { await searchMatches() } }.disabled(
                searching || matchQuery.isEmpty)
            if searching {
                ProgressView()
            } else if matches.isEmpty {
                Text("No matches").foregroundStyle(.secondary)
            }
            ForEach(matches) { entry in
                Button {
                    if let matchingID { model.assign(entry, to: matchingID, library: library) }
                    popup = .review
                } label: {
                    HStack(spacing: 12) {
                        CoverImage(url: entry.coverURL, symbol: "BookOpen").frame(
                            width: 40, height: 56)
                        Text(entry.title).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
    private func searchMatches() async {
        guard !searching else { return }
        searching = true
        defer { searching = false }
        do { matches = try await model.candidates(query: matchQuery) } catch {
            model.notice = "Couldn’t search this source. Try again."
        }
    }
    @ViewBuilder private func popupActions(_ current: TrackingPopup) -> some View {
        switch current {
        case .account:
            Button("Cancel", action: close).disabled(model.working)
            if let service, !service.isLoggedIn {
                Button("Connect") {
                    Task { if await model.connect(service, token: token) { close() } }
                }.disabled(
                    model.working || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .foregroundStyle(NavigationStyle.accent).frame(minHeight: 44)
            }
        case .disconnect:
            Button("Cancel", action: close).disabled(model.working)
            Button("Disconnect", role: .destructive) {
                if let service { Task { if await model.disconnect(service) { close() } } }
            }.disabled(model.working).frame(minHeight: 44)
        case .setup:
            Button("Cancel", action: close).disabled(model.working)
            Button("Continue") {
                Task {
                    if await model.fetchList(library: library) {
                        popup = .review
                        await model.matchPending(library: library)
                    }
                }
            }.disabled(model.working || model.statuses.isEmpty).foregroundStyle(
                NavigationStyle.accent
            )
            .frame(minHeight: 44)
        case .review:
            if model.working {
                Button(model.stopRequested ? "Stopping…" : "Stop") { model.stopRequested = true }
                    .disabled(model.stopRequested).frame(minHeight: 44)
            } else {
                Button("Save & close", action: close)
                Spacer()
                if model.items.contains(where: { $0.state == .pending }) {
                    Button("Resume matching") {
                        Task { await model.matchPending(library: library) }
                    }
                    .foregroundStyle(NavigationStyle.accent).frame(minHeight: 44)
                } else {
                    Button(dryRun ? "Preview import" : "Import \(model.importable.count)") {
                        Task { await model.runImport(library: library, dryRun: dryRun) }
                    }.disabled(model.importable.isEmpty).foregroundStyle(NavigationStyle.accent)
                        .frame(
                            minHeight: 44)
                }
            }
        case .match: Button("Back") { popup = .review }.frame(minHeight: 44)
        case .discard:
            Button("Cancel") { popup = .review }
            Button("Discard", role: .destructive) {
                model.discard()
                popup = .setup
            }.frame(minHeight: 44)
        case .services: Button("Cancel", action: close).frame(minHeight: 44)
        }
    }
}

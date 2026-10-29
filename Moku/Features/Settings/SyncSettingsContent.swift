import SwiftUI

/// Settings → Sync: pair with Moku desktop over the local network and keep the
/// library, folders and reading progress in step.
struct SyncSettingsContent: View {
    @Environment(LibraryStore.self) private var library
    @State private var sync = DesktopSync.shared
    @State private var discovery = DesktopDiscovery()
    @State private var address = ""
    @State private var password = ""
    @State private var chosen: DesktopDiscovery.Desktop?
    @State private var pairing = false
    @State private var notice: String?
    @State private var confirmDisconnect = false
    @AppStorage("sync.automatic") private var automatic = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let paired = sync.pairing {
                connected(paired)
            } else {
                setup
            }
            GeneralSection("What syncs") {
                GeneralRow("Library, folders and progress", detail: "Titles match by source, so the same extension must be installed on both devices. Removing a title on one device removes it on the other.") { EmptyView() }
                GeneralStyle.divider
                GeneralRow("Stays on each device", detail: "Downloads, stars, reading history and app settings.") { EmptyView() }
            }
        }
        .task {
            await sync.load()
            if !sync.isPaired { discovery.start() }
        }
        .onDisappear { discovery.stop() }
        .onChange(of: sync.isPaired) { _, paired in paired ? discovery.stop() : discovery.start() }
        .confirmationDialog("Disconnect from this desktop?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await sync.disconnect() } }
        } message: {
            Text("Nothing is deleted on either device. Sync stops until you connect again.")
        }
    }

    private func connected(_ paired: DesktopPairing) -> some View {
        GeneralSection("Desktop") {
            GeneralRow(paired.name, detail: paired.baseURL.host() ?? paired.baseURL.absoluteString) {
                PhosphorIcon("CheckCircle.fill").foregroundStyle(NavigationStyle.accent)
            }
            GeneralStyle.divider
            GeneralRow("Sync now", detail: status) {
                if sync.syncing {
                    ProgressView()
                } else {
                    Button("Sync") { Task { await sync.sync(library: library) } }
                        .buttonStyle(GeneralTextButtonStyle())
                        .accessibilityIdentifier("sync.now")
                }
            }
            if let report = sync.lastReport, !report.missingOnPhone.isEmpty || !report.missingOnDesktop.isEmpty {
                GeneralStyle.divider
                GeneralRow("Needs an extension", detail: missing(report)) { EmptyView() }
            }
            GeneralStyle.divider
            GeneralRow("Sync automatically", detail: "When you open Moku, at most every five minutes.") {
                Toggle("Sync automatically", isOn: $automatic).toggleStyle(GeneralToggleStyle())
            }
            GeneralStyle.divider
            GeneralRow("Disconnect", detail: "Forget this desktop and its password.") {
                Button("Disconnect") { confirmDisconnect = true }.buttonStyle(GeneralTextButtonStyle())
            }
        }
    }

    private var status: String {
        if sync.syncing { return sync.phase.isEmpty ? "Syncing…" : "\(sync.phase)…" }
        if let error = sync.lastError { return error }
        guard let report = sync.lastReport else { return "Not synced yet." }
        let when = report.finishedAt.formatted(.relative(presentation: .named))
        let failures = report.failures > 0 ? " · \(report.failures) couldn’t sync" : ""
        return "Last synced \(when). \(report.summary)\(failures)"
    }

    private func missing(_ report: DesktopSync.Report) -> String {
        func list(_ items: [String: Int]) -> String {
            items.sorted { $0.value > $1.value }.prefix(3)
                .map { "\($0.key.split(separator: ".").last.map(String.init) ?? $0.key) (\($0.value))" }
                .joined(separator: ", ")
        }
        var lines: [String] = []
        if !report.missingOnPhone.isEmpty { lines.append("Install on this phone: \(list(report.missingOnPhone))") }
        if !report.missingOnDesktop.isEmpty { lines.append("Install on the desktop: \(list(report.missingOnDesktop))") }
        return lines.joined(separator: "\n")
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 20) {
            GeneralSection("Connect to Moku desktop") {
                GeneralRow("On your computer", detail: "Open Moku → Settings → Auth, set a server password, then turn on “Allow devices on your network”.") { EmptyView() }
                GeneralStyle.divider
                if discovery.desktops.isEmpty {
                    GeneralRow(discovery.denied ? "Local network access is off" : "Looking for desktops…",
                               detail: discovery.denied
                                ? "Allow Moku in iOS Settings → Privacy & Security → Local Network, or enter the address below."
                                : "Desktops with phone sync on appear here.") {
                        if !discovery.denied { ProgressView() }
                    }
                } else {
                    ForEach(discovery.desktops) { desktop in
                        GeneralRow(desktop.name, detail: desktop.address.host() ?? "") {
                            Button(chosen == desktop ? "Selected" : "Use") {
                                chosen = desktop
                                address = desktop.address.absoluteString
                            }
                            .buttonStyle(GeneralTextButtonStyle())
                        }
                    }
                }
                GeneralStyle.divider
                GeneralRow("Address", detail: "Shown in desktop Settings → Auth → Phone sync.") {
                    TextField("192.168.1.20:6007", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .generalInput().frame(width: 190)
                        .accessibilityIdentifier("sync.address")
                }
                GeneralRow("Server password", detail: "") {
                    SecureField("Password", text: $password).textContentType(.password)
                        .generalInput().frame(width: 190)
                        .onSubmit { Task { await connect() } }
                        .accessibilityIdentifier("sync.password")
                }
                Button { Task { await connect() } } label: {
                    Group {
                        if pairing { ProgressView().tint(NavigationStyle.background) } else { Text("Connect") }
                    }
                    .font(.headline)
                    .foregroundStyle(NavigationStyle.background)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(NavigationStyle.accent.opacity(address.isEmpty || password.isEmpty ? 0.4 : 1),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(pairing || address.isEmpty || password.isEmpty)
                .padding(.top, 12)
                .accessibilityIdentifier("sync.connect")
                if let notice {
                    Text(notice).font(.footnote).foregroundStyle(.orange)
                        .padding(.top, 8).padding(.bottom, 4)
                        .accessibilityIdentifier("sync.error")
                }
            }
        }
    }

    private func connect() async {
        guard !pairing, let url = DesktopClient.normalize(address) else {
            notice = DesktopSyncError.invalidAddress.errorDescription
            return
        }
        pairing = true
        notice = nil
        defer { pairing = false }
        do {
            let name = chosen?.address == url ? chosen?.name ?? url.host() ?? "Desktop" : url.host() ?? "Desktop"
            let paired = try await DesktopClient.pair(name: name, address: url, password: password)
            password = ""
            await sync.connect(paired)
            await sync.sync(library: library)
        } catch {
            notice = (error as? LocalizedError)?.errorDescription ?? "Couldn’t connect. Try again."
        }
    }
}

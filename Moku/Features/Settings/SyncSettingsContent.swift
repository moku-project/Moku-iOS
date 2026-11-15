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
        SettingsForm {
            if let paired = sync.pairing {
                connected(paired)
            } else {
                setup
            }
            Section {
                SettingsLabel("Library, folders and progress", detail: "Titles match by source, so the same extension must be installed on both devices. Removing a title on one device removes it on the other.")
                SettingsLabel("Stays on each device", detail: "Downloads, stars, reading history and app settings.")
            } header: {
                Text("What syncs")
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

    @ViewBuilder private func connected(_ paired: DesktopPairing) -> some View {
        Section("Desktop") {
            LabeledContent {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(NavigationStyle.accent)
            } label: {
                SettingsLabel(paired.name, detail: paired.baseURL.host() ?? paired.baseURL.absoluteString)
            }
            Button {
                Task { await sync.sync(library: library) }
            } label: {
                HStack {
                    SettingsLabel("Sync now", detail: status)
                    if sync.syncing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(sync.syncing)
            .accessibilityIdentifier("sync.now")
            if let report = sync.lastReport, !report.missingOnPhone.isEmpty || !report.missingOnDesktop.isEmpty {
                Label {
                    SettingsLabel("Needs an extension", detail: missing(report))
                } icon: {
                    Image(systemName: "puzzlepiece.extension").foregroundStyle(.orange)
                }
            }
            SettingsToggle("Sync automatically", detail: "When you open Moku, at most every five minutes.", isOn: $automatic)
        }
        Section {
            Button("Disconnect", role: .destructive) { confirmDisconnect = true }
        } footer: {
            Text("Forget this desktop and its password.")
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

    @ViewBuilder private var setup: some View {
        Section {
            if discovery.desktops.isEmpty {
                HStack {
                    SettingsLabel(discovery.denied ? "Local network access is off" : "Looking for desktops…",
                                  detail: discovery.denied
                                    ? "Allow Moku in iOS Settings → Privacy & Security → Local Network, or enter the address below."
                                    : "Desktops with phone sync on appear here.")
                    if !discovery.denied {
                        Spacer()
                        ProgressView()
                    }
                }
            } else {
                ForEach(discovery.desktops) { desktop in
                    Button {
                        chosen = desktop
                        address = desktop.address.absoluteString
                    } label: {
                        HStack {
                            SettingsLabel(desktop.name, detail: desktop.address.host() ?? "")
                            Spacer()
                            if chosen == desktop {
                                Image(systemName: "checkmark").foregroundStyle(NavigationStyle.accent)
                            }
                        }
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(chosen == desktop ? .isSelected : [])
                }
            }
        } header: {
            Text("Connect to Moku desktop")
        } footer: {
            Text("On your computer, open Moku → Settings → Auth, set a server password, then turn on “Allow devices on your network”.")
        }
        Section {
            TextField("Address, such as 192.168.1.20:6007", text: $address)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("sync.address")
            SecureField("Server password", text: $password).textContentType(.password)
                .onSubmit { Task { await connect() } }
                .accessibilityIdentifier("sync.password")
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    Text("Connect")
                    if pairing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(pairing || address.isEmpty || password.isEmpty)
            .accessibilityIdentifier("sync.connect")
        } footer: {
            if let notice {
                Text(notice).foregroundStyle(.orange).accessibilityIdentifier("sync.error")
            } else {
                Text("The address is shown in desktop Settings → Auth → Phone sync.")
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

import SwiftUI

/// Moku Sync: pair devices on the local network to keep library, progress and history in step.
struct SyncSettingsContent: View {
    @State private var sync = MokuSync()
    @State private var draftName = ""
    @State private var renaming = false
    @State private var pairing = false
    @State private var unpairing: MokuSync.Peer?

    var body: some View {
        SettingsForm {
            if let status = sync.status {
                if status.name == nil {
                    nameSection
                } else {
                    deviceSection(status)
                    peersSection(status)
                    if !status.missingExtensions.isEmpty { missingSection(status) }
                }
            } else if sync.working {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let error = sync.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            Section {
                SettingsLabel(
                    "Syncs",
                    detail: "Library, folders, reading progress, bookmarks and reading history.")
                SettingsLabel(
                    "Stays on each device",
                    detail:
                        "Extensions and downloads. Titles from a missing extension appear once it's installed."
                )
            } footer: {
                Text("Devices sync directly over your local network. No account or cloud.")
            }
        }
        .task { await sync.load() }
        .refreshable { await sync.load() }
        .sheet(isPresented: $pairing, onDismiss: { Task { await sync.load() } }) {
            PairDeviceSheet(sync: sync).themedColorScheme()
        }
        .alert("Device Name", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { save() }
        }
        .confirmationDialog(
            "Unpair \(unpairing?.name ?? "")?",
            isPresented: Binding(get: { unpairing != nil }, set: { if !$0 { unpairing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Unpair", role: .destructive) {
                if let peer = unpairing { Task { await sync.unpair(peer) } }
            }
        } message: {
            Text("Nothing is deleted. The devices stop syncing until you pair again.")
        }
    }

    private var nameSection: some View {
        Section {
            TextField("Device Name", text: $draftName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit(save)
            Button("Continue", action: save)
                .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Name This Device")
        } footer: {
            Text("Other devices show this name when pairing.")
        }
    }

    private func deviceSection(_ status: MokuSync.Status) -> some View {
        Section {
            Button {
                draftName = status.name ?? ""
                renaming = true
            } label: {
                LabeledContent("This Device", value: status.name ?? "")
            }
            .foregroundStyle(.primary)
            ForEach(MokuSync.displayAddresses(status.addresses), id: \.self) { address in
                Button {
                    UIPasteboard.general.string = address
                    Toaster.shared.show("Address copied")
                } label: {
                    LabeledContent("Address") {
                        Text(address).font(.body.monospaced()).textSelection(.enabled)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityHint("Copies the address")
            }
            Button("Pair a Device", systemImage: "plus.circle") { pairing = true }
            Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                Task { await sync.syncNow() }
            }
            .disabled(sync.working || status.peers.isEmpty)
        } footer: {
            if status.pendingTitles > 0 {
                Text(
                    "\(counted(status.pendingTitles, "synced title")) still loading from their sources."
                )
            }
        }
    }

    private func peersSection(_ status: MokuSync.Status) -> some View {
        Section("Paired Devices") {
            if status.peers.isEmpty {
                Text("No paired devices").foregroundStyle(.secondary)
            }
            ForEach(status.peers) { peer in
                HStack(spacing: 12) {
                    Circle().fill(peer.online ? Color.green : Color.secondary.opacity(0.4)).frame(
                        width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(peer.name)
                        Text(seen(peer)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .swipeActions {
                    Button("Unpair", role: .destructive) { unpairing = peer }
                }
            }
        }
    }

    private func missingSection(_ status: MokuSync.Status) -> some View {
        Section {
            ForEach(status.missingExtensions) { missing in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(missing.name)
                        Text(
                            ([counted(missing.titles, "title")] + missing.examples.prefix(2))
                                .joined(separator: " · ")
                        )
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Install") { Task { await sync.install(missing) } }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                        .disabled(sync.working)
                }
            }
        } header: {
            Text("Missing Extensions")
        } footer: {
            Text("Synced titles from these extensions appear once they're installed.")
        }
    }

    private func seen(_ peer: MokuSync.Peer) -> String {
        if peer.online { return "Connected" }
        guard let date = MokuSync.date(peer.lastSeenAt) else { return "Not seen yet" }
        return "Last seen " + date.formatted(.relative(presentation: .named))
    }

    private func save() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task { await sync.rename(name) }
    }
}

/// Shows this device's one-time code, or enters another device's code and previews the merge before pairing.
private struct PairDeviceSheet: View {
    let sync: MokuSync
    @Environment(\.dismiss) private var dismiss
    @State private var code: MokuSync.Code?
    @State private var nearby: [MokuSync.Nearby] = []
    @State private var searching = false
    @State private var address = ""
    @State private var entered = ""
    @State private var preview: MokuSync.Preview?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    previewSection(preview)
                } else {
                    showCodeSection
                    enterCodeSection
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(
                            .orange)
                    }
                }
            }
            .navigationTitle("Pair a Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .tint(NavigationStyle.accent)
            .task { await search() }
        }
    }

    private var showCodeSection: some View {
        Section {
            if let code {
                VStack(spacing: 6) {
                    Text(code.code).font(
                        .system(.largeTitle, design: .monospaced).weight(.semibold)
                    )
                    .textSelection(.enabled)
                    if let address = MokuSync.displayAddresses(sync.status?.addresses ?? []).first {
                        Text(address).font(.title3.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let expires = MokuSync.date(code.expiresAt) {
                        Text("Expires \(expires.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            } else {
                Button("Show Pairing Code", systemImage: "number") {
                    Task {
                        do { code = try await sync.createCode() } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
            }
        } header: {
            Text("On This Device")
        } footer: {
            Text("On the other device, type this address and code.")
        }
    }

    private var enterCodeSection: some View {
        Section {
            ForEach(nearby.filter { !$0.paired }) { device in
                Button {
                    address = device.address
                } label: {
                    HStack {
                        Label(device.name, systemImage: "desktopcomputer")
                        Spacer()
                        if address == device.address { Image(systemName: "checkmark") }
                    }
                }
                .foregroundStyle(.primary)
            }
            if searching { ProgressView().frame(maxWidth: .infinity) }
            TextField("Address, like 192.168.1.20", text: $address)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Pairing Code", text: $entered)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            Button("Continue") { Task { await loadPreview() } }
                .disabled(
                    busy || MokuSync.address(address) == nil
                        || entered.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            HStack {
                Text("Another Device's Code")
                Spacer()
                Button("Search", systemImage: "arrow.clockwise") { Task { await search() } }
                    .labelStyle(.iconOnly).disabled(searching)
            }
        } footer: {
            Text("Pick a nearby device or type its address, then enter the code it shows.")
        }
    }

    private func previewSection(_ preview: MokuSync.Preview) -> some View {
        Section {
            LabeledContent("Their titles", value: "\(preview.titles)")
            LabeledContent("New here", value: "\(preview.newTitles)")
            LabeledContent("Sent to them", value: "\(preview.sentTitles)")
            LabeledContent("Folders", value: "\(preview.folders)")
            LabeledContent("Chapters read", value: "\(preview.readChapters)")
            if !preview.mergingFolders.isEmpty {
                LabeledContent(
                    "Merging folders", value: preview.mergingFolders.joined(separator: ", "))
            }
            Button("Pair with \(preview.name)") { Task { await connect(preview) } }
                .bold().disabled(busy)
            Button("Back", role: .cancel) { self.preview = nil }
        } header: {
            Text("Pair with \(preview.name)?")
        } footer: {
            Text("Both libraries merge. Nothing is removed from either device.")
        }
    }

    private func search() async {
        searching = true
        defer { searching = false }
        nearby = (try? await sync.nearby()) ?? []
    }

    private func loadPreview() async {
        guard let target = MokuSync.address(address) else { return }
        busy = true
        defer { busy = false }
        do {
            preview = try await sync.preview(
                address: target, code: entered.trimmingCharacters(in: .whitespaces))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func connect(_ preview: MokuSync.Preview) async {
        guard let target = MokuSync.address(address) else { return }
        busy = true
        defer { busy = false }
        do {
            try await sync.connect(
                address: target, code: entered.trimmingCharacters(in: .whitespaces),
                node: preview.node)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

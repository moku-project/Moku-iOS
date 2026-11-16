import Foundation
import Observation

/// Tsunagu's device-to-device sync: pairing, paired devices and titles waiting on extensions.
@MainActor @Observable final class MokuSync {
    struct Peer: Decodable, Identifiable, Sendable {
        let node: String
        let name: String
        let address: String?
        let lastSeenAt: String?
        let online: Bool
        var id: String { node }
    }
    struct MissingExtension: Decodable, Identifiable, Sendable {
        let packageName: String
        let name: String
        let titles: Int
        let examples: [String]
        var id: String { packageName }
    }
    struct Status: Decodable, Sendable {
        let node: String
        let name: String?
        let peers: [Peer]
        let pendingTitles: Int
        let addresses: [String]
        let missingExtensions: [MissingExtension]
    }
    struct Nearby: Decodable, Identifiable, Sendable {
        let node: String
        let name: String
        let address: String
        let paired: Bool
        var id: String { node }
    }
    struct Code: Decodable, Sendable {
        let code: String
        let expiresAt: String
    }
    struct Preview: Decodable, Sendable {
        let node: String
        let name: String
        let titles: Int
        let newTitles: Int
        let sentTitles: Int
        let folders: Int
        let readChapters: Int
        let mergingFolders: [String]
    }

    private(set) var status: Status?
    private(set) var working = false
    var error: String?

    private static let statusFields =
        "node name pendingTitles addresses peers { node name address lastSeenAt online } missingExtensions { packageName name titles examples }"

    func load() async {
        await run { () async throws -> Status in
            struct R: Decodable, Sendable { let syncStatus: Status }
            let r: R = try await BackendAPI.shared.graphql(
                "{ syncStatus { \(Self.statusFields) } }", requiresSourceRuntime: false)
            return r.syncStatus
        }
    }

    func rename(_ name: String) async {
        await mutateStatus("setSyncDeviceName(name: \(BackendAPI.literal(name)))")
        await Backend.shared.refreshSync()
    }

    func syncNow() async { await mutateStatus("syncNow") }

    func unpair(_ peer: Peer) async {
        await mutateStatus("removeSyncPeer(node: \(BackendAPI.literal(peer.node)))")
    }

    func install(_ missing: MissingExtension) async {
        working = true
        defer { working = false }
        do {
            struct R: Decodable, Sendable {
                struct E: Decodable, Sendable { let id: String }
                let installSyncExtension: E
            }
            let _: R = try await BackendAPI.shared.graphql(
                "mutation { installSyncExtension(packageName: \(BackendAPI.literal(missing.packageName))) { id } }"
            )
        } catch {
            self.error = error.localizedDescription
        }
        await load()
    }

    func createCode() async throws -> Code {
        struct R: Decodable, Sendable { let createSyncPairingCode: Code }
        let r: R = try await BackendAPI.shared.graphql(
            "mutation { createSyncPairingCode { code expiresAt } }", requiresSourceRuntime: false)
        return r.createSyncPairingCode
    }

    func nearby() async throws -> [Nearby] {
        struct R: Decodable, Sendable { let syncNearby: [Nearby] }
        let r: R = try await BackendAPI.shared.graphql(
            "{ syncNearby { node name address paired } }", requiresSourceRuntime: false)
        return r.syncNearby
    }

    func preview(address: String, code: String) async throws -> Preview {
        struct R: Decodable, Sendable { let previewSyncPeer: Preview }
        let r: R = try await BackendAPI.shared.graphql(
            "mutation { previewSyncPeer(address: \(BackendAPI.literal(address)), code: \(BackendAPI.literal(code))) { node name titles newTitles sentTitles folders readChapters mergingFolders } }",
            requiresSourceRuntime: false)
        return r.previewSyncPeer
    }

    func connect(address: String, code: String, node: String) async throws {
        struct R: Decodable, Sendable { let connectSyncPeer: Peer }
        let _: R = try await BackendAPI.shared.graphql(
            "mutation { connectSyncPeer(address: \(BackendAPI.literal(address)), code: \(BackendAPI.literal(code)), node: \(BackendAPI.literal(node))) { node name address lastSeenAt online } }",
            requiresSourceRuntime: false)
        await load()
    }

    /// Accepts "192.168.1.20", "host:6008" or a full URL; Tsunagu's sync port is 6008.
    /// The pairing QR code Moku desktop and Android use: moku://pair?node=…&name=…&code=…&addr=… (one addr each).
    struct PairLink: Equatable, Sendable {
        let node: String?
        let name: String?
        let code: String
        let addresses: [String]

        nonisolated init(node: String?, name: String?, code: String, addresses: [String]) {
            self.node = node
            self.name = name
            self.code = code
            self.addresses = addresses
        }

        nonisolated init?(_ text: String) {
            guard
                let parts = URLComponents(
                    string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                parts.scheme == "moku", parts.host == "pair"
            else { return nil }
            let items = parts.queryItems ?? []
            let value = { (name: String) in items.first { $0.name == name }?.value }
            let addresses = items.filter { $0.name == "addr" }.compactMap(\.value).filter {
                !$0.isEmpty
            }
            guard let code = value("code"), !code.isEmpty, !addresses.isEmpty else { return nil }
            self.init(node: value("node"), name: value("name"), code: code, addresses: addresses)
        }

        nonisolated var url: String {
            var parts = URLComponents()
            parts.scheme = "moku"
            parts.host = "pair"
            parts.queryItems =
                [("node", node), ("name", name), ("code", code)].compactMap { key, value in
                    value.map { URLQueryItem(name: key, value: $0) }
                } + addresses.map { URLQueryItem(name: "addr", value: $0) }
            return parts.string ?? ""
        }
    }

    /// The addresses worth typing on another device, shortest form first: IPv4, no scheme, no default port.
    nonisolated static func displayAddresses(_ addresses: [String]) -> [String] {
        let shown = addresses.compactMap { raw -> String? in
            guard let parts = URLComponents(string: raw.contains("://") ? raw : "http://" + raw),
                let host = parts.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
                !host.isEmpty, host != "localhost",
                !host.hasPrefix("127."), !host.lowercased().hasPrefix("fe80"), host != "::1"
            else { return nil }
            let name = host.contains(":") ? "[\(host)]" : host
            return parts.port == nil || parts.port == 6008 ? name : "\(name):\(parts.port!)"
        }
        var seen = Set<String>()
        let unique = shown.filter { seen.insert($0).inserted }
        return unique.filter { !$0.hasPrefix("[") } + unique.filter { $0.hasPrefix("[") }
    }

    nonisolated static func address(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard
            var parts = URLComponents(
                string: trimmed.contains("://") ? trimmed : "http://" + trimmed),
            parts.scheme == "http" || parts.scheme == "https", let host = parts.host, !host.isEmpty
        else { return nil }
        parts.port = parts.port ?? 6008
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        return parts.string
    }

    private func mutateStatus(_ field: String) async {
        await run { () async throws -> Status in
            struct R: Decodable, Sendable { let value: Status }
            let r: R = try await BackendAPI.shared.graphql(
                "mutation { value: \(field) { \(Self.statusFields) } }",
                requiresSourceRuntime: false)
            return r.value
        }
    }

    private func run(_ work: () async throws -> Status) async {
        working = true
        defer { working = false }
        do {
            status = try await work()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    nonisolated static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

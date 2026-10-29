import Foundation
import Security

/// A paired desktop: its server address plus credentials kept in the Keychain.
/// The password is stored so an expired 30-day session can renew itself
/// without asking the user to pair again.
struct DesktopPairing: Codable, Equatable, Sendable {
    var name: String
    var baseURL: URL
    var token: String
    var password: String
}

enum DesktopSyncError: LocalizedError, Equatable {
    case invalidAddress, unreachable, wrongPassword, noPassword, server(String)
    var errorDescription: String? {
        switch self {
        case .invalidAddress: "Enter an address like 192.168.1.20:6007."
        case .unreachable:
            "Couldn’t reach the desktop. Check that both devices are on the same network and phone sync is on in Moku desktop → Settings → Auth."
        case .wrongPassword: "That password doesn’t match the desktop server password."
        case .noPassword: "Set a server password in Moku desktop → Settings → Auth, then turn on phone sync."
        case .server(let message): message
        }
    }
}

enum DesktopPairingStore {
    private static let service = "com.moku.desktop-sync"
    private static let account = "pairing"

    static func load() -> DesktopPairing? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(DesktopPairing.self, from: data)
    }

    @discardableResult static func save(_ pairing: DesktopPairing) -> Bool {
        guard let data = try? JSONEncoder().encode(pairing) else { return false }
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func clear() { SecItemDelete(base as CFDictionary) }

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

/// GraphQL against a desktop Tsunagu server over the local network.
actor DesktopClient {
    private(set) var pairing: DesktopPairing
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    init(pairing: DesktopPairing) { self.pairing = pairing }

    /// Accepts "host", "host:port" or a full URL; the desktop listens on 6007.
    nonisolated static func normalize(_ address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard var parts = URLComponents(string: text), let host = parts.host, !host.isEmpty,
            parts.scheme == "http" || parts.scheme == "https"
        else { return nil }
        if parts.port == nil { parts.port = 6007 }
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }

    /// Checks reachability and the password, returning a signed-in pairing.
    static func pair(name: String, address: URL, password: String) async throws -> DesktopPairing {
        let session = URLSession(configuration: .ephemeral)
        var status = URLRequest(url: address.appending(path: "api/auth/status"))
        status.timeoutInterval = 8
        let required: Bool
        do {
            let (data, response) = try await session.data(for: status)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DesktopSyncError.unreachable }
            struct Status: Decodable { let passwordRequired: Bool }
            required = try JSONDecoder().decode(Status.self, from: data).passwordRequired
        } catch let error as DesktopSyncError { throw error } catch { throw DesktopSyncError.unreachable }
        // Never pair with a desktop that accepts anyone on the network.
        guard required else { throw DesktopSyncError.noPassword }
        let token = try await login(session: session, address: address, password: password)
        return DesktopPairing(name: name, baseURL: address, token: token, password: password)
    }

    private static func login(session: URLSession, address: URL, password: String) async throws -> String {
        var request = URLRequest(url: address.appending(path: "api/auth/login"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["password": password])
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw DesktopSyncError.unreachable }
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200:
            struct Login: Decodable { let token: String }
            guard let token = try? JSONDecoder().decode(Login.self, from: data).token else {
                throw DesktopSyncError.server("The desktop sent an unexpected sign-in response.")
            }
            return token
        case 401: throw DesktopSyncError.wrongPassword
        default: throw DesktopSyncError.unreachable
        }
    }

    func graphql<T: Decodable & Sendable>(_ query: String) async throws -> T {
        do {
            return try await send(query)
        } catch DesktopSyncError.wrongPassword {
            // Sessions last 30 days; renew once with the saved password.
            pairing.token = try await Self.login(session: session, address: pairing.baseURL, password: pairing.password)
            DesktopPairingStore.save(pairing)
            return try await send(query)
        }
    }

    private func send<T: Decodable & Sendable>(_ query: String) async throws -> T {
        var request = URLRequest(url: pairing.baseURL.appending(path: "api/graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw DesktopSyncError.unreachable }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw DesktopSyncError.wrongPassword }
        guard (200..<300).contains(status) else { throw DesktopSyncError.unreachable }
        let envelope = try JSONDecoder().decode(DesktopEnvelope<T>.self, from: data)
        if let message = envelope.errors?.first?.message { throw DesktopSyncError.server(message) }
        guard let value = envelope.data else { throw DesktopSyncError.server("The desktop returned no data.") }
        return value
    }
}

private struct DesktopEnvelope<T: Decodable>: Decodable {
    struct Message: Decodable { let message: String }
    let data: T?
    let errors: [Message]?
}

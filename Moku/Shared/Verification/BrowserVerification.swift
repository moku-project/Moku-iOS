import Foundation
import Tsunagu
import WebKit

/// Bridge to Tsunagu's browser verification; the stateless gomobile `Service` reaches the shared core on its own serial queue.
enum BrowserVerification {
    struct Session: Decodable, Sendable, Identifiable {
        let id: String
        let extensionId: String
        let url: URL
        let state: String
    }

    /// Field names match the sandbox's `BrowserState` / `BrowserCookie` (PersistentCookieStore.kt).
    struct State: Codable, Sendable {
        var cookies: [Cookie]
        var userAgent: String
    }

    struct Cookie: Codable, Sendable {
        var name: String
        var value: String
        var domain: String
        var path: String
        var expiresAt: Int64
        var secure: Bool
        var httpOnly: Bool
        var hostOnly: Bool
        var persistent: Bool

        init(_ cookie: HTTPCookie) {
            name = cookie.name
            value = cookie.value
            domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            path = cookie.path
            secure = cookie.isSecure
            httpOnly = cookie.isHTTPOnly
            hostOnly = !cookie.domain.hasPrefix(".")
            persistent = cookie.expiresDate != nil
            expiresAt = cookie.expiresDate.map { Int64($0.timeIntervalSince1970 * 1000) } ?? Int64.max
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            value = try container.decode(String.self, forKey: .value)
            domain = try container.decode(String.self, forKey: .domain)
            path = try container.decodeIfPresent(String.self, forKey: .path) ?? "/"
            expiresAt = try container.decodeIfPresent(Int64.self, forKey: .expiresAt) ?? Int64.max
            secure = try container.decodeIfPresent(Bool.self, forKey: .secure) ?? false
            httpOnly = try container.decodeIfPresent(Bool.self, forKey: .httpOnly) ?? false
            hostOnly = try container.decodeIfPresent(Bool.self, forKey: .hostOnly) ?? true
            persistent = try container.decodeIfPresent(Bool.self, forKey: .persistent) ?? true
        }

        var native: HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: hostOnly ? domain : "." + domain,
                .path: path, .secure: secure ? "TRUE" : "FALSE",
            ]
            if persistent, expiresAt != Int64.max {
                properties[.expires] = Date(timeIntervalSince1970: Double(expiresAt) / 1000)
            }
            if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            return HTTPCookie(properties: properties)
        }

        /// True when the cookie would be sent to `host`.
        func applies(to host: String) -> Bool {
            host == domain || (!hostOnly && host.hasSuffix("." + domain))
        }
    }

    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "The source runtime isn’t available. Restart the app and try again." }
    }

    /// True for `BackendAPI`'s `SOURCE_CLOUDFLARE` message (a challenge page or a 403).
    static func isChallenge(_ message: String?) -> Bool {
        guard let message else { return false }
        return message.localizedCaseInsensitiveContains("Cloudflare")
            || message.localizedCaseInsensitiveContains("bot protection")
    }
    static func isChallenge(_ error: any Error) -> Bool {
        isChallenge((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    static func begin(extensionID: String, url: URL) async throws -> Session {
        // The sandbox (JVM) must be up: sessions read and write its cookie store.
        _ = try await Backend.shared.connection()
        let json: String = try await worker.perform { service in
            var error: NSError?
            let result = service.beginBrowserVerification(extensionID, url: url.absoluteString, error: &error)
            if let error { throw error }
            return result
        }
        return try JSONDecoder().decode(Session.self, from: Data(json.utf8))
    }

    static func cookies(sessionID: String) async throws -> State {
        let json: String = try await worker.perform { service in
            var error: NSError?
            let result = service.browserCookies(sessionID, error: &error)
            if let error { throw error }
            return result
        }
        return try JSONDecoder().decode(State.self, from: Data(json.utf8))
    }

    static func complete(sessionID: String, state: State) async throws {
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        try await worker.perform { try $0.completeBrowserVerification(sessionID, stateJSON: json) }
    }

    static func cancel(sessionID: String) async {
        try? await worker.perform { $0.cancelBrowserVerification(sessionID) }
    }

    private static let worker = Worker()

    /// Confines the non-Sendable gomobile handle to one serial queue.
    private final class Worker: @unchecked Sendable {
        private let queue = DispatchQueue(label: "moku.go.verification", qos: .userInitiated)
        private var service: BackendService?

        func perform<T: Sendable>(_ operation: @escaping @Sendable (BackendService) throws -> T) async throws -> T {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if self.service == nil { self.service = BackendNewService() }
                    guard let service = self.service else {
                        continuation.resume(throwing: Failure.unavailable)
                        return
                    }
                    do { continuation.resume(returning: try operation(service)) } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

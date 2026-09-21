import Foundation
import WebKit

/// Service bridge for a host-presented, manually completed source challenge.
/// This type owns no product navigation or buttons.
@MainActor
public final class SourceVerificationBrowser {
    public let webView: WKWebView
    public let session: BackendController.VerificationSession
    private let backend: BackendController
    private var finished = false

    public init(session: BackendController.VerificationSession, backend: BackendController) {
        self.session = session
        self.backend = backend
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
    }

    public func load() async throws {
        let state = try await backend.verificationCookies(sessionID: session.id)
        let decoded = try JSONDecoder().decode(BrowserState.self, from: Data(state.utf8))
        if !decoded.userAgent.isEmpty { webView.customUserAgent = decoded.userAgent }
        for cookie in decoded.cookies {
            if let native = cookie.native {
                await webView.configuration.websiteDataStore.httpCookieStore.setCookie(native)
            }
        }
        // No backend bearer credential is attached to this source request.
        webView.load(URLRequest(url: session.url))
    }

    /// The host calls this after the user finishes verification. Cookie transfer
    /// does not assert success: the original source operation is retried once.
    public func complete(retry: @Sendable () async throws -> Void) async throws {
        guard !finished else { throw BackendController.BackendError.invalidEndpoint }
        let agent = try await webView.evaluateJavaScript("navigator.userAgent") as? String ?? ""
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        let host = session.url.host ?? ""
        let selected = cookies.filter {
            let domain = $0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain
            return host == domain || ($0.domain.hasPrefix(".") && host.hasSuffix("." + domain))
        }
        let data = try JSONEncoder().encode(BrowserState(cookies: selected.map(BrowserCookie.init), userAgent: agent))
        try await backend.completeVerification(sessionID: session.id, state: String(decoding: data, as: UTF8.self))
        finished = true
        webView.stopLoading()
        try await retry()
    }

    public func cancel() async {
        guard !finished else { return }
        finished = true
        webView.stopLoading()
        await backend.cancelVerification(sessionID: session.id)
    }
}

private struct BrowserState: Codable {
    var cookies: [BrowserCookie]
    var userAgent: String
}
private struct BrowserCookie: Codable {
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
        name = cookie.name; value = cookie.value
        domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
        path = cookie.path; secure = cookie.isSecure; httpOnly = cookie.isHTTPOnly
        hostOnly = !cookie.domain.hasPrefix(".")
        persistent = cookie.expiresDate != nil
        expiresAt = cookie.expiresDate.map { Int64($0.timeIntervalSince1970 * 1000) } ?? Int64.max
    }
    var native: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: hostOnly ? domain : "." + domain,
            .path: path, .secure: secure ? "TRUE" : "FALSE"
        ]
        if persistent { properties[.expires] = Date(timeIntervalSince1970: Double(expiresAt) / 1000) }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}

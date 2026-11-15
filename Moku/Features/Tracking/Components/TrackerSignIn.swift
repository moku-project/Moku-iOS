import SwiftUI
import WebKit

/// Tracker redirects target web URLs, not an app scheme, so a web view catches them and passes them to `trackerLogin`.
enum TrackerSignIn {
    /// The custom URL scheme of the authorization URL's `redirect_uri`, if any.
    static func callbackScheme(for url: URL) -> String? {
        guard let redirect = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "redirect_uri" })?.value,
            let scheme = URL(string: redirect)?.scheme?.lowercased(),
            scheme != "http", scheme != "https"
        else { return nil }
        return scheme
    }

    /// The value to send to `trackerLogin` when `url` is the tracker's redirect.
    static func credential(in url: URL, expectedState: String?) -> String? {
        let text = url.absoluteString
        if text.contains("access_token=") { return text }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            items.contains(where: { $0.name == "code" && $0.value?.isEmpty == false }),
            let state = items.first(where: { $0.name == "state" })?.value,
            expectedState == nil || state == expectedState
        else { return nil }
        return text
    }

    /// The tracker refused or the user denied access on the redirect.
    static func denial(in url: URL) -> String? {
        let fragment = URLComponents(string: "?" + (url.fragment ?? ""))?.queryItems ?? []
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let error = (query + fragment).first(where: { $0.name == "error" })?.value else { return nil }
        return (query + fragment).first(where: { $0.name == "error_description" })?.value ?? error
    }

    static func state(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "state" })?.value
    }
}

/// Sheet that shows the tracker's authorization page and returns the redirected URL.
struct TrackerSignInSheet: View {
    let service: TrackingService
    let url: URL
    /// Called with the redirected URL; returns whether sign-in succeeded.
    let finish: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var browser: TrackerSignInBrowser?
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Group {
                if let browser {
                    WebViewContainer(webView: browser.webView)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .top) {
                            if browser.isLoading {
                                ProgressView(value: browser.progress).progressViewStyle(.linear)
                            }
                        }
                } else {
                    Color.clear
                }
            }
            .overlay {
                if working {
                    ProgressView("Signing in…")
                        .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle("Sign in to \(service.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }.disabled(working)
                }
            }
            .alert(
                "Couldn’t sign in",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button("Try Again") { browser?.restart() }
                Button("Cancel", role: .cancel) { dismiss() }
            } message: {
                Text(failure ?? "")
            }
        }
        .interactiveDismissDisabled(working)
        .task {
            guard browser == nil else { return }
            browser = TrackerSignInBrowser(url: url) { result in
                switch result {
                case .credential(let value):
                    Task {
                        working = true
                        let success = await finish(value)
                        working = false
                        if success { dismiss() } else {
                            failure = "\(service.name) didn’t accept the sign-in. Try again, or paste a token instead."
                        }
                    }
                case .denied(let message):
                    failure = message
                }
            }
        }
    }
}

@MainActor @Observable
final class TrackerSignInBrowser: NSObject, WKNavigationDelegate {
    enum Result { case credential(String), denied(String) }

    private(set) var isLoading = false
    private(set) var progress = 0.0
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private let url: URL
    @ObservationIgnored private let expectedState: String?
    @ObservationIgnored private let handler: (Result) -> Void
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var delivered = false

    init(url: URL, handler: @escaping (Result) -> Void) {
        self.url = url
        self.expectedState = TrackerSignIn.state(in: url)
        self.handler = handler
        let configuration = WKWebViewConfiguration()
        // Signing out of Moku must not leave a tracker session behind in the app.
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        observations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                let loading = view.isLoading
                Task { @MainActor in self?.isLoading = loading }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                let value = view.estimatedProgress
                Task { @MainActor in self?.progress = value }
            },
            // Same-document fragment changes never reach the navigation delegate.
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                let current = view.url
                Task { @MainActor in if let current { _ = self?.inspect(current) } }
            },
        ]
        webView.load(URLRequest(url: url))
    }

    func restart() {
        delivered = false
        webView.load(URLRequest(url: url))
    }

    /// True when `url` was the redirect and has been handled.
    private func inspect(_ url: URL) -> Bool {
        guard !delivered else { return true }
        if let credential = TrackerSignIn.credential(in: url, expectedState: expectedState) {
            delivered = true
            webView.stopLoading()
            handler(.credential(credential))
            return true
        }
        if url.absoluteString != self.url.absoluteString, let denial = TrackerSignIn.denial(in: url) {
            delivered = true
            webView.stopLoading()
            handler(.denied(denial))
            return true
        }
        return false
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }
        return inspect(url) ? .cancel : .allow
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

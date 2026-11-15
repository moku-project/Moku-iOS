import SwiftUI
import WebKit

// MARK: - Presenting

/// One request to show a source's site so the user can pass its challenge.
struct SourceVerificationRequest: Identifiable {
    let id = UUID()
    let extensionID: String
    /// The page that failed. Nil asks for the site address (Tsunagu doesn't expose a source's base URL).
    let url: URL?
    var sourceName: String?
    /// Runs after the browser state is saved, e.g. to retry the failed load.
    var onComplete: (@MainActor () -> Void)?
}

/// `@Environment(\.presentSourceVerification) var verify` then
/// `verify(extensionID: source.packageName, url: url) { retry() }`.
/// Works under any view with `.sourceVerificationHost()` above it.
struct SourceVerificationAction {
    fileprivate var present: @MainActor (SourceVerificationRequest) -> Void = { _ in }
    /// False when no `.sourceVerificationHost()` is installed above this view.
    var isAvailable = false

    @MainActor func callAsFunction(
        extensionID: String, url: URL?, sourceName: String? = nil,
        onComplete: (@MainActor () -> Void)? = nil
    ) {
        present(.init(extensionID: extensionID, url: url, sourceName: sourceName, onComplete: onComplete))
    }
}

extension EnvironmentValues {
    @Entry var presentSourceVerification = SourceVerificationAction()
}

extension View {
    /// Installs `\.presentSourceVerification` for this subtree and presents its sheet.
    func sourceVerificationHost() -> some View { modifier(SourceVerificationHost()) }
}

private struct SourceVerificationHost: ViewModifier {
    @State private var request: SourceVerificationRequest?

    func body(content: Content) -> some View {
        content
            .environment(
                \.presentSourceVerification,
                SourceVerificationAction(present: { request = $0 }, isAvailable: true)
            )
            .sheet(item: $request) { SourceVerificationView(request: $0) }
    }
}

// MARK: - Sheet

struct SourceVerificationView: View {
    let request: SourceVerificationRequest
    @Environment(\.dismiss) private var dismiss
    @State private var model = SourceVerificationModel()
    @State private var address = ""

    private var title: String {
        if let name = request.sourceName { return "Verify \(name)" }
        if let host = model.session?.url.host ?? request.url?.host { return host }
        return "Verify Source"
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) {
                            Task {
                                await model.cancel()
                                dismiss()
                            }
                        }
                        .disabled(model.phase == .saving)
                        .accessibilityIdentifier("verification.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if model.phase == .saving {
                            ProgressView()
                        } else {
                            Button("Done") {
                                Task {
                                    if await model.complete() {
                                        Toaster.shared.show("Verification saved")
                                        dismiss()
                                        request.onComplete?()
                                    }
                                }
                            }
                            .disabled(model.phase != .ready)
                            .accessibilityIdentifier("verification.done")
                        }
                    }
                    if model.phase == .ready {
                        ToolbarItem(placement: .bottomBar) {
                            Button {
                                model.webView.reload()
                            } label: {
                                Label("Reload", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                }
                .interactiveDismissDisabled(model.session != nil)
        }
        .task {
            // The caller's page first, then the source's own site as Tsunagu reports it,
            // then the address used last time.
            var url = request.url
            if url == nil { url = await Self.sourceSite(request.extensionID) }
            address = url?.absoluteString
                ?? UserDefaults.standard.string(forKey: Self.addressKey(request.extensionID)) ?? "https://"
            if let url { await start(url) }
        }
        .onDisappear { Task { await model.cancel() } }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .failed:
            addressForm
        case .starting:
            ProgressView("Opening site…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready, .saving:
            VerificationWebView(webView: model.webView)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if model.isLoading {
                        ProgressView(value: model.progress).progressViewStyle(.linear)
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    Text("Complete the check on this page, then tap Done.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(.bar)
                }
        }
    }

    private var addressForm: some View {
        Form {
            Section {
                TextField("https://example.com", text: $address)
                    .keyboardType(.URL).textContentType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { open() }
                    .accessibilityIdentifier("verification.address")
                Button("Open Site") { open() }
                    .disabled(Self.url(from: address) == nil)
            } header: {
                Text("Site address")
            } footer: {
                Text("Enter the source’s website. Pass its check in the page that opens, then tap Done so the source can load with the same browser session.")
            }
            if case .failed(let message) = model.phase {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(NavigationStyle.background.ignoresSafeArea())
    }

    private func open() {
        guard let url = Self.url(from: address) else { return }
        Task { await start(url) }
    }

    private func start(_ url: URL) async {
        if await model.start(extensionID: request.extensionID, url: url) {
            UserDefaults.standard.set(url.absoluteString, forKey: Self.addressKey(request.extensionID))
        }
    }

    private static func addressKey(_ extensionID: String) -> String { "verification.url.\(extensionID)" }

    /// The site the installed source reads from, once the extension host has loaded it.
    private static func sourceSite(_ extensionID: String) async -> URL? {
        struct Result: Decodable, Sendable {
            struct Item: Decodable, Sendable { let packageName: String; let baseUrl: String? }
            let installedExtensions: [Item]
        }
        guard let result: Result = try? await BackendAPI.shared.graphql(
            "{ installedExtensions { packageName baseUrl } }", requiresSourceRuntime: false),
            let site = result.installedExtensions.first(where: { $0.packageName == extensionID })?.baseUrl
        else { return nil }
        return url(from: site)
    }

    private static func url(from text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = "https://" + value }
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            let host = url.host, host.contains(".")
        else { return nil }
        return url
    }
}

// MARK: - Model

@MainActor @Observable
final class SourceVerificationModel: NSObject {
    enum Phase: Equatable { case idle, starting, ready, saving, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var session: BrowserVerification.Session?
    private(set) var isLoading = false
    private(set) var progress = 0.0
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var finished = false

    override init() {
        let configuration = WKWebViewConfiguration()
        // Only the cookies seeded for this site, and what the page sets, come back at Done.
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        observations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                let loading = view.isLoading
                Task { @MainActor in self?.isLoading = loading }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                let value = view.estimatedProgress
                Task { @MainActor in self?.progress = value }
            },
        ]
    }

    func start(extensionID: String, url: URL) async -> Bool {
        guard phase != .starting else { return false }
        phase = .starting
        do {
            if let old = session {
                session = nil
                await BrowserVerification.cancel(sessionID: old.id)
            }
            let started = try await BrowserVerification.begin(extensionID: extensionID, url: url)
            session = started
            finished = false
            let state = try await BrowserVerification.cookies(sessionID: started.id)
            if !state.userAgent.isEmpty { webView.customUserAgent = state.userAgent }
            let store = webView.configuration.websiteDataStore.httpCookieStore
            for cookie in state.cookies {
                if let native = cookie.native { await store.setCookie(native) }
            }
            webView.load(URLRequest(url: started.url))
            phase = .ready
            return true
        } catch {
            if let session { await BrowserVerification.cancel(sessionID: session.id) }
            session = nil
            phase = .failed(Self.message(error))
            return false
        }
    }

    /// Hands the page's cookies and User-Agent for the session's site to the source.
    func complete() async -> Bool {
        guard let session, phase == .ready else { return false }
        phase = .saving
        do {
            var agent = webView.customUserAgent ?? ""
            if agent.isEmpty {
                agent = (try? await webView.evaluateJavaScript("navigator.userAgent") as? String) ?? ""
            }
            let all = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            let host = (webView.url?.host ?? session.url.host ?? "").lowercased()
            let sessionHost = (session.url.host ?? "").lowercased()
            let cookies = all.map(BrowserVerification.Cookie.init).filter {
                $0.applies(to: sessionHost) || $0.applies(to: host)
            }
            try await BrowserVerification.complete(
                sessionID: session.id, state: .init(cookies: cookies, userAgent: agent))
            finished = true
            webView.stopLoading()
            return true
        } catch {
            phase = .ready
            Toaster.shared.show("Couldn’t save the verification. Try again.", kind: .error)
            return false
        }
    }

    func cancel() async {
        guard !finished else { return }
        finished = true
        webView.stopLoading()
        if let session { await BrowserVerification.cancel(sessionID: session.id) }
    }

    private static func message(_ error: any Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if text.contains("public source URL") { return "Enter the source’s public website address." }
        if text.contains("unknown source") { return "This source isn’t installed." }
        if text.contains("invalid source URL") { return "That address isn’t valid. Use the site’s https:// address." }
        return text.isEmpty ? "Couldn’t open this site. Try again." : text
    }
}

private struct VerificationWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

import Foundation
import Network
import Observation

/// Finds Moku desktops that advertise `_moku._tcp` (desktop Settings → Auth →
/// Phone sync), and resolves each to an IPv4 address the client can reach.
@MainActor @Observable final class DesktopDiscovery {
    struct Desktop: Identifiable, Equatable, Sendable {
        let name: String
        let address: URL
        var id: String { name }
    }

    private(set) var desktops: [Desktop] = []
    private(set) var searching = false
    private(set) var denied = false
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var resolving: [String: NWConnection] = [:]

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_moku._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.searching = true
                case .failed, .cancelled: self?.searching = false
                case .waiting(let error):
                    // Local network permission declined shows up as a DNS-SD policy error.
                    if case .dns(let code) = error, code == -65570 { self?.denied = true }
                    self?.searching = false
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.update(results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolving.values.forEach { $0.cancel() }
        resolving.removeAll()
        searching = false
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var names = Set<String>()
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            names.insert(name)
            guard resolving[name] == nil, !desktops.contains(where: { $0.name == name }) else { continue }
            resolve(name: name, endpoint: result.endpoint)
        }
        desktops.removeAll { !names.contains($0.name) }
    }

    /// A short-lived connection yields the service's host and port.
    private func resolve(name: String, endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        resolving[name] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            switch state {
            case .ready:
                let remote = connection.currentPath?.remoteEndpoint
                connection.cancel()
                Task { @MainActor in
                    self?.resolving[name] = nil
                    guard case .hostPort(let host, let port) = remote else { return }
                    let text: String
                    switch host {
                    // Drop a scoped interface suffix such as "%en0".
                    case .ipv4(let address): text = String("\(address)".split(separator: "%").first ?? "")
                    case .name(let value, _): text = value
                    default: return
                    }
                    guard let url = DesktopClient.normalize("\(text):\(port.rawValue)") else { return }
                    self?.desktops.removeAll { $0.name == name }
                    self?.desktops.append(Desktop(name: name, address: url))
                }
            case .failed, .cancelled:
                Task { @MainActor in self?.resolving[name] = nil }
            default: break
            }
        }
        connection.start(queue: .main)
    }
}

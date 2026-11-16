import Foundation
import Network
import Tsunagu

/// Tsunagu's `_moku._tcp` discovery for iOS, which can't open multicast sockets itself; Go calls `browse` off the main thread.
final class SyncBrowser: NSObject, BackendSyncDiscoveryProtocol, @unchecked Sendable {
    private struct Found: Encodable, Sendable { let node, name, address: String }

    func browse(_ waitMillis: Int64, error: NSErrorPointer) -> String {
        do { return try discover(waitMillis) } catch let failure as NSError {
            error?.pointee = failure
            return "[]"
        }
    }

    private func discover(_ waitMillis: Int64) throws -> String {
        let total = Double(max(waitMillis, 400)) / 1000
        let deadline = DispatchTime.now() + total
        let queue = DispatchQueue(label: "moku.sync.browse")
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_moku._tcp", domain: nil), using: .tcp)
        let results = Locked<Set<NWBrowser.Result>>([])
        browser.browseResultsChangedHandler = { latest, _ in results.set(latest) }
        browser.start(queue: queue)
        // Spend most of the window listening, the rest resolving addresses.
        Thread.sleep(forTimeInterval: total * 0.6)
        browser.cancel()

        let found = Locked<[Found]>([])
        let group = DispatchGroup()
        for result in results.value {
            guard case .bonjour(let txt) = result.metadata,
                let node = txt.dictionary["node"], !node.isEmpty
            else { continue }
            let name = txt.dictionary["name"] ?? node
            group.enter()
            resolve(result.endpoint, queue: queue) { address in
                if let address { found.update { $0.append(Found(node: node, name: name, address: address)) } }
                group.leave()
            }
        }
        _ = group.wait(timeout: deadline)
        let data = try JSONEncoder().encode(found.value)
        return String(decoding: data, as: UTF8.self)
    }

    /// Connecting is the only Network.framework way to learn a service's IP; the connection closes right away.
    private func resolve(_ endpoint: NWEndpoint, queue: DispatchQueue, done: @escaping @Sendable (String?) -> Void) {
        let parameters = NWParameters.tcp
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(to: endpoint, using: parameters)
        let once = OnceFlag()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var address: String?
                if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint {
                    let ip = "\(host)".split(separator: "%").first.map(String.init) ?? "\(host)"
                    address = "http://\(ip):\(port.rawValue)"
                }
                connection.cancel()
                if once.claim() { done(address) }
            case .failed, .cancelled:
                if once.claim() { done(nil) }
            default: break
            }
        }
        connection.start(queue: queue)
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func set(_ value: Value) { lock.withLock { stored = value } }
    func update(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool { lock.withLock { defer { used = true }; return !used } }
}

/// Publishes this device as `_moku._tcp` with the port and TXT record Tsunagu reports.
@MainActor public final class SyncAdvertiser: NSObject {
    public static let shared = SyncAdvertiser()
    private var service: NetService?
    private var published = ""

    /// Pass `SyncAdvert()`'s JSON; an empty string stops advertising.
    public func update(_ advert: String) {
        guard advert != published else { return }
        service?.stop()
        service = nil
        published = advert
        struct Advert: Decodable { let type: String; let name: String; let port: Int32; let txt: [String: String] }
        guard let data = advert.data(using: .utf8), let value = try? JSONDecoder().decode(Advert.self, from: data) else { return }
        let next = NetService(domain: "local.", type: value.type + ".", name: value.name, port: value.port)
        next.setTXTRecord(NetService.data(fromTXTRecord: value.txt.mapValues { Data($0.utf8) }))
        next.publish()
        service = next
    }
}

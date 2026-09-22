import Foundation
import Tsunagu

/// Own one controller for the app's embedded backend. Blocking native calls use
/// a dedicated serial queue; neither MainActor nor Swift's cooperative pool waits on Go.
public actor BackendController {
    public enum State: String, Sendable {
        case stopped, starting, running, stopping, failed
    }

    /// Endpoint returned by TSJavaRuntime after starting the app's JVM sandbox.
    public struct EmbeddedSandbox: Sendable {
        let address: String
        let token: String
        public init(address: String, token: String) {
            self.address = address
            self.token = token
        }
    }

    public struct CoreStatus: Decodable, Sendable {
        public let name: String
        public let mode: String
        public let migrations: Int
        public let graphqlAvailable: Bool
        public let extensionsAvailable: Bool
        public let capabilities: [String: Bool]
        public let limitations: [String]
    }

    public enum BackendError: Error {
        case invalidTransition(State)
        case invalidEndpoint
        case unhealthyResponse
    }

    public struct VerificationSession: Decodable, Sendable {
        public let id: String
        public let extensionId: String
        public let url: URL
        public let state: String
    }
    public func beginBrowserVerification(extensionID: String, url: URL) async throws -> VerificationSession {
        let json = try await worker.perform { service in
            var error: NSError?
            let result = service.beginBrowserVerification(extensionID, url: url.absoluteString, error: &error)
            if let error { throw error }
            return result
        }
        return try JSONDecoder().decode(VerificationSession.self, from: Data(json.utf8))
    }
    public func verificationCookies(sessionID: String) async throws -> String {
        try await worker.perform { service in
            var error: NSError?
            let result = service.browserCookies(sessionID, error: &error)
            if let error { throw error }
            return result
        }
    }
    public func completeVerification(sessionID: String, state: String) async throws {
        try await worker.perform { try $0.completeBrowserVerification(sessionID, stateJSON: state) }
    }
    public func cancelVerification(sessionID: String) async {
        try? await worker.perform { $0.cancelBrowserVerification(sessionID) }
    }
    public func importLocalFile(_ source: URL, kind: String, series: String, chapter: String, name: String) async throws {
        try await worker.perform { service in
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            try service.importLocalFile(source.path, kind: kind, series: series, chapter: chapter, name: name)
        }
    }

    private let worker = NativeServiceWorker()
    public private(set) var state: State = .stopped
    private var connection: Connection?
    private var restartConfiguration: (URL, EmbeddedSandbox?, Bool)?

    public init() {}

    /// Call on foreground loss. The JVM remains alive; workers stop and unfinished
    /// downloads become retryable. Resume returns a fresh authenticated connection.
    public func suspend() async throws { try await stop() }
    @discardableResult
    public func resume() async throws -> Connection {
        guard let (directory, sandbox, deferSandbox) = restartConfiguration else { throw BackendError.invalidEndpoint }
        return try await start(dataDirectory: directory, sandbox: sandbox, deferSandbox: deferSandbox)
    }


    /// Supply an app-owned Application Support directory. The caller decides
    /// when startup happens; blocking native work always runs on the worker queue.
    @discardableResult
    public func start(dataDirectory: URL, sandbox: EmbeddedSandbox? = nil, deferSandbox: Bool = false) async throws
        -> Connection
    {
        guard state == .stopped else { throw BackendError.invalidTransition(state) }
        guard dataDirectory.isFileURL else { throw BackendError.invalidEndpoint }
        try Task.checkCancellation()
        state = .starting
        restartConfiguration = (dataDirectory, sandbox, deferSandbox)
        do {
            let result = try await worker.start(dataDirectory: dataDirectory, sandbox: sandbox, deferSandbox: deferSandbox)
            let status = try await Self.fetchStatus(result)
            guard status.mode == "embedded-core", status.migrations > 0 else {
                throw BackendError.unhealthyResponse
            }
            try Task.checkCancellation()
            connection = result
            state = .running
            return result
        } catch {
            do {
                try await worker.stop()
                state = .stopped
            } catch {
                state = .failed
            }
            connection = nil
            throw error
        }
    }

    public func attachSandbox(_ sandbox: EmbeddedSandbox) async throws {
        guard state == .running else { throw BackendError.invalidTransition(state) }
        try await worker.perform { try $0.attachSandbox(sandbox.address, token: sandbox.token) }
        if let (directory, _, _) = restartConfiguration {
            restartConfiguration = (directory, sandbox, false)
        }
    }

    public func status() async throws -> CoreStatus {
        guard state == .running, let connection else {
            throw BackendError.invalidTransition(state)
        }
        return try await Self.fetchStatus(connection)
    }

    public func stop() async throws {
        guard state != .starting && state != .stopping else {
            throw BackendError.invalidTransition(state)
        }
        if state == .stopped { return }
        state = .stopping
        defer { connection = nil }
        do {
            try await worker.stop()
            state = .stopped
        } catch {
            state = .failed
            throw error
        }
    }

    private static func fetchStatus(_ connection: Connection) async throws -> CoreStatus {
        // The local server doesn't redirect. Refuse redirects so its credential
        // can never be forwarded to another endpoint.
        let session = URLSession(
            configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: connection.statusRequest())
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BackendError.unhealthyResponse
        }
        return try JSONDecoder().decode(CoreStatus.self, from: data)
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// All access to the non-Sendable gomobile object is confined to `queue`.
/// The unchecked conformance transfers the worker, never the native service.
private final class NativeServiceWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "moku.go.lifecycle", qos: .utility)
    private var service: BackendService?

    func perform<T: Sendable>(_ operation: @escaping @Sendable (BackendService) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                guard let service = self.service else {
                    continuation.resume(throwing: BackendController.BackendError.unhealthyResponse)
                    return
                }
                do { continuation.resume(returning: try operation(service)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    func start(dataDirectory: URL, sandbox: BackendController.EmbeddedSandbox?, deferSandbox: Bool) async throws
        -> BackendController.Connection
    {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                do {
                    guard let service = self.service ?? BackendNewService() else {
                        throw BackendController.BackendError.unhealthyResponse
                    }
                    try service.setVideoEngine(TSVideoEngine())
                    self.service = service
                    if let sandbox {
                        try service.start(
                            withSandbox: dataDirectory.path, address: sandbox.address,
                            token: sandbox.token)
                    } else if deferSandbox {
                        try service.startDeferredSandbox(dataDirectory.path)
                    } else {
                        try service.start(dataDirectory.path)
                    }
                    guard let url = URL(string: service.baseURL()),
                        url.scheme == "http", url.host == "127.0.0.1", url.port != nil
                    else { throw BackendController.BackendError.invalidEndpoint }
                    continuation.resume(
                        returning: BackendController.Connection(
                            baseURL: url, token: service.accessToken()))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                do {
                    try self.service?.stop()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

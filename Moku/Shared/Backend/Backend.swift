import Foundation

/// One runtime per process. JVM startup runs on a dedicated queue, never on MainActor.
actor Backend {
    static let shared = Backend()
    private let controller = BackendController()
    private var startup: Task<BackendController.Connection, Error>?

    #if DEBUG
        /// Uses a disposable database and the real authenticated content server.
        func preparePlayerUITest() async throws {
            guard ProcessInfo.processInfo.arguments.contains("--ui-testing-isolated-backend")
            else {
                throw EmbeddedSearchError.message("Player tests require an isolated backend.")
            }
            _ = try await connection()
            let video = Bundle.main.url(forResource: "player-preview", withExtension: "mp4")!
            for episode in 1...3 {
                try await controller.importLocalFile(
                    video, kind: "anime", series: "Player Fixture",
                    chapter: "Episode \(episode)", name: "episode.mp4")
            }
        }
    #endif

    /// Local SQLite reads do not depend on Java, extension loading, or source networking.
    func connection(requiresSourceRuntime: Bool = true, manualStart: Bool = false) async throws
        -> BackendController.Connection
    {
        // A screen that has already disappeared must not boot either service.
        try Task.checkCancellation()
        guard !PreviewMode.isEnabled else {
            throw EmbeddedSearchError.message("Backend access is disabled in UI previews.")
        }
        if startup == nil {
            guard
                manualStart
                    || (UserDefaults.standard.object(forKey: "backend.autoStart") as? Bool
                        ?? true)
            else {
                throw EmbeddedSearchError.message(
                    "Automatic server startup is off. Start the server in Settings → General.")
            }
            let controller = controller
            startup = Task {
                let directory = try self.dataDirectory()
                return try await controller.start(dataDirectory: directory, deferSandbox: true)
            }
        }
        let connection = try await startup!.value
        try Task.checkCancellation()
        if requiresSourceRuntime {
            if sourceStartup == nil {
                sourceStartup = Task { try await self.startSourceRuntime() }
            }
            try await sourceStartup!.value
            try Task.checkCancellation()
        }
        return connection
    }

    func importLocalFile(_ url: URL, kind: String, series: String, chapter: String) async throws {
        _ = try await connection(requiresSourceRuntime: false)
        try await controller.importLocalFile(url, kind: kind, series: series, chapter: chapter, name: url.lastPathComponent)
    }

    func currentServerURL() async -> URL? {
        guard let startup else { return nil }
        return try? await startup.value.baseURL
    }

    private var sourceStartup: Task<Void, Error>?
    private var directory: URL?

    private func dataDirectory() throws -> URL {
        if let directory { return directory }
        var directoryName = "Backend"
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-isolated-backend") {
                directoryName = "UITestBackend-" + UUID().uuidString
            }
        #endif
        let result = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true
        ).appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        directory = result
        return result
    }

    private func startSourceRuntime() async throws {
        guard let home = Bundle.main.resourceURL,
            FileManager.default.fileExists(
                atPath: home.appendingPathComponent("Sandbox.jar").path)
        else {
            throw EmbeddedSearchError.message(
                "The embedded runtime is missing. Rebuild the app.")
        }
        let directory = try dataDirectory()
        let jar = home.appendingPathComponent("Sandbox.jar")
        let token = UUID().uuidString + UUID().uuidString
        let port: Int = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(label: "moku.jvm.startup", qos: .utility).async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                var startupError: NSError?
                let port = TSJavaRuntime.startSandbox(
                    withRuntimeHome: home.path, classPath: jar.path,
                    dataDirectory: directory.path, token: token, error: &startupError)
                if let startupError {
                    continuation.resume(
                        throwing: EmbeddedSearchError.message(
                            "The source runtime could not start. Restart the app. (\(startupError.code))"
                        ))
                } else if port > 0 {
                    continuation.resume(returning: port)
                } else {
                    continuation.resume(
                        throwing: EmbeddedSearchError.message(
                            "The source runtime could not start. Restart the app."))
                }
            }
        }
        try await controller.attachSandbox(.init(address: "127.0.0.1:\(port)", token: token))
        guard try await controller.status().extensionsAvailable else {
            throw EmbeddedSearchError.message(
                "The source runtime is not ready. Restart the app.")
        }
        // sourceStartup retains failure too: this process must never start a second JVM.
        // The independent SQLite connection remains usable after a JVM failure.
    }

}

enum EmbeddedSearchError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}

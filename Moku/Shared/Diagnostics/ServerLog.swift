import Foundation

/// Desktop's server log counterpart. The embedded server (Go's `log` and the
/// source sandbox) writes to stdout and stderr, which iOS discards outside Xcode.
/// Both are teed into a size-capped file in Caches, and still reach the original
/// descriptors so the Xcode console keeps working.
final class ServerLog: @unchecked Sendable {
    static let shared = ServerLog()
    /// About 1 MB on disk; older output is trimmed to half when the cap is reached.
    private static let limit = 1_000_000

    let url: URL
    private let queue = DispatchQueue(label: "dev.moku.server-log", qos: .utility)
    private var handle: FileHandle?
    private var size = 0
    private var pipes: [Pipe] = []
    private var started = false

    private init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "Logs", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "server.log")
    }

    func start() {
        queue.sync {
            guard !started else { return }
            started = true
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            size = Int((try? handle?.seekToEnd()) ?? 0)
            setvbuf(stdout, nil, _IOLBF, 0)
            capture(STDOUT_FILENO)
            capture(STDERR_FILENO)
        }
    }

    private func capture(_ descriptor: Int32) {
        let original = dup(descriptor)
        guard original >= 0 else { return }
        let pipe = Pipe()
        guard dup2(pipe.fileHandleForWriting.fileDescriptor, descriptor) >= 0 else {
            close(original)
            return
        }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] reader in
            let data = reader.availableData
            guard !data.isEmpty else { return }
            data.withUnsafeBytes { _ = write(original, $0.baseAddress, data.count) }
            self?.append(data)
        }
        pipes.append(pipe)
    }

    private func append(_ data: Data) {
        queue.async { [self] in
            guard let handle else { return }
            try? handle.write(contentsOf: data)
            size += data.count
            guard size > Self.limit else { return }
            // Keep the newest half, starting at a line boundary.
            try? handle.synchronize()
            guard var kept = try? Data(contentsOf: url).suffix(Self.limit / 2) else { return }
            if let newline = kept.firstIndex(of: 0x0A) { kept = kept.suffix(from: kept.index(after: newline)) }
            try? handle.truncate(atOffset: 0)
            try? handle.write(contentsOf: kept)
            size = kept.count
        }
    }

    /// The newest output, at most `bytes` long.
    func tail(bytes: Int = 256_000) async -> String {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                try? handle?.synchronize()
                let data = (try? Data(contentsOf: url)) ?? Data()
                var tail = data.suffix(bytes)
                if data.count > bytes, let newline = tail.firstIndex(of: 0x0A) {
                    tail = tail.suffix(from: tail.index(after: newline))
                }
                continuation.resume(returning: String(decoding: tail, as: UTF8.self))
            }
        }
    }

    func clear() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                try? handle?.truncate(atOffset: 0)
                size = 0
                continuation.resume()
            }
        }
    }
}

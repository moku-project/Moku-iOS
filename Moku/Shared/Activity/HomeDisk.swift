import Foundation

actor HomeDisk {
    let url: URL
    init(url: URL) { self.url = url }

    func read() throws -> HomeSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(HomeSnapshot.self, from: Data(contentsOf: url))
    }

    func write(_ snapshot: HomeSnapshot) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}

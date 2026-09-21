import Foundation

@main
struct Smoke {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moku-backend-smoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = BackendController()
        let connection = try await backend.start(dataDirectory: directory)
        let status = try await backend.status()
        guard status.name == "Tsunagu", status.migrations == 18,
              status.graphqlAvailable, !status.extensionsAvailable else {
            fatalError("Unexpected embedded backend capabilities")
        }
        let local = directory.appendingPathComponent("input.html")
        try Data("<p>Offline local novel.</p>".utf8).write(to: local)
        try await backend.importLocalFile(local, kind: "novels", series: "Local", chapter: "Chapter 1", name: "chapter.html")
        let (text, response) = try await URLSession.shared.data(for: connection.contentRequest(path: "/content/1/1/text"))
        guard (response as? HTTPURLResponse)?.statusCode == 200, String(decoding: text, as: UTF8.self).contains("Offline local novel.") else {
            fatalError("Native import did not produce readable content")
        }
        try await backend.suspend()
        _ = try await backend.resume()
        try await backend.stop()
        try await backend.stop()
        print("Swift → Go → migrated SQLite → authenticated HTTP → restart: PASS")
    }
}

import Foundation

struct StorageUsage: Sendable {
    let total: Int64
    let covers: Int64
    let available: Int64
}
actor SettingsStorage {
    private var root: URL { URL.applicationSupportDirectory }
    private var covers: URL { root.appending(path: "Backend/media/covers") }
    func usage() throws -> StorageUsage {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: root.path)
        return StorageUsage(
            total: size(root) + size(URL.cachesDirectory.appending(path: "Moku")),
            covers: size(covers) + size(URL.cachesDirectory.appending(path: "Moku")),
            available: (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0)
    }
    func clearCovers() throws {
        guard FileManager.default.fileExists(atPath: covers.path) else { return }
        // Remove only cache files, leaving the directory available to concurrent requests.
        for url in try FileManager.default.contentsOfDirectory(
            at: covers, includingPropertiesForKeys: [.isRegularFileKey])
        {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
    private func size(_ url: URL) -> Int64 {
        guard
            let files = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            guard
                let values = try? file.resourceValues(forKeys: [
                    .isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey,
                ]), values.isRegularFile == true, values.isSymbolicLink != true
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

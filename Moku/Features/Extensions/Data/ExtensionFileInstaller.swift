import Foundation
import UniformTypeIdentifiers

/// Uploads an .apk, .jar or .js extension to the embedded server.
enum ExtensionFileInstaller {
    static let contentTypes: [UTType] = ["apk", "jar", "js"].compactMap { UTType(filenameExtension: $0) } + [.data]

    /// Returns the installed extension's name.
    static func install(_ url: URL) async throws -> String {
        let (data, filename) = try await Task.detached {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard ["apk", "jar", "js"].contains(url.pathExtension.lowercased()) else {
                throw EmbeddedSearchError.message("Choose an .apk, .jar or .js extension file.")
            }
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= 64 * 1024 * 1024 else {
                throw EmbeddedSearchError.message("This file is empty or larger than 64 MB.")
            }
            return (try Data(contentsOf: url), url.lastPathComponent)
        }.value
        let boundary = "Moku-" + UUID().uuidString
        let safeName = filename.replacingOccurrences(of: "\"", with: "")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        // The server installs through the extension sandbox, which starts on demand.
        _ = try await Backend.shared.connection()
        let response = try await BackendAPI.shared.api(
            path: "/api/extensions/install-file", method: "POST", body: body,
            contentType: "multipart/form-data; boundary=\(boundary)")
        struct Result: Decodable { let name: String? }
        return (try? JSONDecoder().decode(Result.self, from: response))?.name ?? ""
    }
}

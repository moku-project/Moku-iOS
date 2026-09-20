import SwiftUI

struct CacheFileInfo: Identifiable, Sendable {
    let id: String
    let bytes: Int64
    let modified: Date
}
struct CacheSettingsContent: View {
    @State private var files: [CacheFileInfo] = []
    @State private var busy = false
    @State private var expanded = false
    var body: some View {
        GeneralSection("Cache") {
            GeneralRow("Entries", detail: "Stored cover and search results.") { Text("\(files.count)").font(.system(size: 14)) }
            GeneralStyle.divider
            GeneralRow("Size", detail: "") { Text(ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.bytes }, countStyle: .file)).font(.system(size: 14)) }
            if let oldest = files.first, let newest = files.last {
                GeneralStyle.divider
                GeneralRow("Oldest access", detail: "") { Text(oldest.modified, style: .date).font(.system(size: 14)) }
                GeneralStyle.divider
                GeneralRow("Newest access", detail: "") { Text(newest.modified, style: .date).font(.system(size: 14)) }
            }
            GeneralStyle.divider
            GeneralRow("Stored keys", detail: "") { Button(expanded ? "Hide" : "Show") { expanded.toggle() }.buttonStyle(GeneralTextButtonStyle()) }
            if expanded {
                ForEach(files.prefix(100)) { file in Text(file.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(GeneralStyle.faint).textSelection(.enabled).lineLimit(2) }
            }
            GeneralStyle.divider
            GeneralRow("Cache", detail: "Remove cached covers and search results.") {
                HStack(spacing: 16) {
                    Button("Refresh") { Task { await refresh() } }
                    Button("Clear") { Task { await BackendAPI.shared.clearContentCache(); await refresh() } }
                }.buttonStyle(GeneralTextButtonStyle())
            }
        }.disabled(busy).task { await refresh() }
    }
    private func refresh() async {
        busy = true
        files = await Task.detached { Self.cacheFiles() }.value
        busy = false
    }
    nonisolated private static func cacheFiles() -> [CacheFileInfo] {
            let root = URL.cachesDirectory.appending(path: "Moku")
            guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]) else { return [CacheFileInfo]() }
            var result: [CacheFileInfo] = []
            for case let file as URL in iterator {
                guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]), values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                result.append(CacheFileInfo(id: file.path.replacingOccurrences(of: root.path + "/", with: ""), bytes: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast))
            }
            return result.sorted { $0.modified < $1.modified }
    }
}

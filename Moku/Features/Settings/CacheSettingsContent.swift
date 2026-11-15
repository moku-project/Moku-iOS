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
        Section {
            LabeledContent("Entries", value: "\(files.count)")
                .task { await refresh() }
            LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.bytes }, countStyle: .file))
            if let oldest = files.first, let newest = files.last {
                LabeledContent("Oldest access") { Text(oldest.modified, style: .date) }
                LabeledContent("Newest access") { Text(newest.modified, style: .date) }
            }
            DisclosureGroup("Stored keys", isExpanded: $expanded) {
                ForEach(files.prefix(100)) { file in
                    Text(file.id).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .textSelection(.enabled).lineLimit(2)
                }
            }
            Button("Refresh") { Task { await refresh() } }.disabled(busy)
            Button("Clear cache", role: .destructive) {
                Task { await BackendAPI.shared.clearContentCache(); await refresh() }
            }.disabled(busy)
        } header: {
            Text("Cache")
        } footer: {
            Text("Stored covers and search results.")
        }
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

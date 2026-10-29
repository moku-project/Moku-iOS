import SwiftUI
import UniformTypeIdentifiers

struct SettingsExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct StorageSettingsContent: View {
    @Environment(AppDataStore.self) private var appData
    @State private var localLibraryOpen = false
    @Environment(LibraryStore.self) private var library
    @Environment(ReaderPreferences.self) private var reader
    @State private var model = StoragePreferences()
    @State private var server = ServerPreferences()
    @AppStorage("preferences.storageLimitGB") private var limitGB = 0
    @AppStorage("downloads.autoRetry") private var autoRetry = false
    @State private var document = SettingsExportDocument()
    @State private var exportName = "Moku-settings.json"
    @State private var exporting = false
    @State private var importing = false
    @State private var importKind = "settings"
    @State private var pendingImport: URL?
    @State private var confirmation: StorageAction?
    @State private var path = ""
    @State private var migrate = true
    @State private var localPath = ""
    @State private var localKind = "manga"
    @State private var localSeries = ""
    @State private var localChapter = ""
    enum StorageAction: Identifiable {
        case clear(String, String), deleteBackup(String), importBackup(String), convert, relocate, relocateLocal, resetPreferences
        var id: String { String(describing: self) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GeneralSection("Storage") {
                if let info = model.info {
                    value("Server data", bytes(info.usedBytes))
                    GeneralStyle.divider
                    value("Available space", bytes(info.freeBytes))
                    ForEach(info.categories) { item in
                        GeneralStyle.divider
                        GeneralRow(item.label, detail: "\(bytes(item.bytes)) · \(item.fileCount) files") {
                            if item.clearable {
                                Button("Clear") { confirmation = .clear(item.key, item.label) }.buttonStyle(GeneralTextButtonStyle())
                            }
                        }
                    }
                } else if model.busy { ProgressView().frame(minHeight: 44) }
                GeneralRow("Storage usage", detail: "") {
                    Button("Refresh") { Task { await model.load() } }.buttonStyle(GeneralTextButtonStyle())
                }
            }
            GeneralSection("Downloads") {
                if let setting = server.values.first(where: { $0.key == "manga_download_format" }) {
                    ServerPreferenceRow(setting: setting, model: server)
                    GeneralStyle.divider
                    GeneralRow("Convert existing downloads", detail: "Use the selected download format.") {
                        Button("Convert") { confirmation = .convert }.buttonStyle(GeneralTextButtonStyle())
                    }
                }
                GeneralStyle.divider
                GeneralRow("Retry failed downloads", detail: "Retry once per minute while Downloads is open.") {
                    Toggle("Retry failed downloads", isOn: $autoRetry).toggleStyle(GeneralToggleStyle())
                }
            }
            GeneralSection("Storage limit") {
                GeneralRow("Warn at", detail: "0 disables the storage warning.") {
                    ChoicePicker(title: "", selection: $limitGB, options: [0, 1, 2, 5, 10, 20, 50, 100].map { ($0, $0 == 0 ? "Off" : "\($0) GB") }).font(.subheadline)
                }
                if let info = model.info, limitGB > 0, info.usedBytes >= Double(limitGB) * 1_073_741_824 {
                    Text("Storage limit reached.").font(.footnote).foregroundStyle(GeneralStyle.faint).padding(.vertical, 14)
                }
            }
            GeneralSection("Directories") {
                value("Downloads", server.values.first { $0.key == "downloads_dir" }?.value.nonempty ?? model.info?.mediaDir ?? "—")
                GeneralStyle.divider
                GeneralRow("Downloads directory", detail: "Choose a directory within server data.") {
                    TextField("Directory name", text: $path).textInputAutocapitalization(.never).autocorrectionDisabled().generalInput().frame(width: 150)
                }
                GeneralRow("Move existing files", detail: "Migrate downloads to the new directory.") { Toggle("Move existing files", isOn: $migrate).toggleStyle(GeneralToggleStyle()) }
                GeneralRow("Downloads path", detail: "") {
                    Button("Change") { confirmation = .relocate }.buttonStyle(GeneralTextButtonStyle()).disabled(!validDirectoryName)
                }
                GeneralStyle.divider
                GeneralRow("Local source", detail: "Scan imported local manga, novels, and video.") {
                    Button("Rescan") { Task { await model.run("rescanLocalMedia { id }") } }.buttonStyle(GeneralTextButtonStyle())
                }
                GeneralStyle.divider
                GeneralRow("Local titles", detail: "See and delete imported series.") {
                    Button("Manage") { localLibraryOpen = true }.buttonStyle(GeneralTextButtonStyle())
                        .sheet(isPresented: $localLibraryOpen) { LocalLibrarySheet() }
                }
            }
            GeneralSection("Local files") {
                GeneralRow("Media type", detail: "") { ChoicePicker(title: "", selection: $localKind, options: [("manga", "Manga"), ("novels", "Novels"), ("anime", "Anime")]).font(.subheadline) }
                GeneralStyle.divider
                GeneralRow("Series", detail: "") { TextField("Series title", text: $localSeries).generalInput().frame(width: 150) }
                GeneralStyle.divider
                GeneralRow("Chapter or episode", detail: "") { TextField("Chapter name", text: $localChapter).generalInput().frame(width: 150) }
                GeneralRow("Local file", detail: "Copy a file from Files into the local source.") {
                    Button("Import") { importKind = "local file"; importing = true }.buttonStyle(GeneralTextButtonStyle()).disabled(!validComponent(localSeries) || !validComponent(localChapter))
                }
                GeneralStyle.divider
                GeneralRow("Local source directory", detail: "Choose a directory within server data.") { TextField("Directory name", text: $localPath).textInputAutocapitalization(.never).autocorrectionDisabled().generalInput().frame(width: 150) }
                GeneralRow("Move local files", detail: "Move existing files to the new directory.") {
                    Button("Change") { confirmation = .relocateLocal }.buttonStyle(GeneralTextButtonStyle()).disabled(!validComponent(localPath))
                }
            }
            GeneralSection("Backups") {
                GeneralRow("Server database", detail: "Create a consistent database snapshot.") {
                    Button("Back up") { Task { await model.run("createDatabaseBackup { name }") } }.buttonStyle(GeneralTextButtonStyle())
                }
                GeneralStyle.divider
                GeneralRow("Mihon library", detail: "Export the server library as a .tachibk backup.") {
                    Button("Export") { Task { await model.run("exportMihonBackup { name }") } }.buttonStyle(GeneralTextButtonStyle())
                }
                GeneralRow("Import Mihon backup", detail: "Merge a .tachibk backup from Files.") {
                    Button("Import") { importKind = "Mihon backup"; importing = true }.buttonStyle(GeneralTextButtonStyle())
                }
                ForEach(model.backups) { backup in
                    GeneralStyle.divider
                    GeneralRow(backup.name, detail: "\(bytes(backup.bytes)) · \(backup.createdAt)") {
                        OverflowMenu {
                            Button("Save to Files") { Task {
                                do { document = SettingsExportDocument(data: try await model.backupData(backup)); exportName = backup.name; exporting = true }
                                catch { model.notice = "Couldn’t export this backup." }
                            }}
                            if backup.kind != "sqlite" && backup.name.hasSuffix(".tachibk") {
                                Button("Import library") { confirmation = .importBackup(backup.name) }
                            }
                            Button("Delete", role: .destructive) { confirmation = .deleteBackup(backup.name) }
                        } label: { Text("Manage").font(.subheadline).foregroundStyle(GeneralStyle.text).frame(minHeight: 44) }
                    }
                }
                GeneralStyle.divider
                GeneralRow("App library", detail: "Export locally saved titles.") {
                    Button("Export") { exportLibrary() }.buttonStyle(GeneralTextButtonStyle())
                }
                GeneralRow("Import app library", detail: "Merge titles from a Moku library JSON file.") {
                    Button("Import") { importKind = "library"; importing = true }.buttonStyle(GeneralTextButtonStyle())
                }
                GeneralStyle.divider
                GeneralRow("Export settings", detail: "Save app preferences without passwords or PINs.") {
                    Button("Export") { exportSettings() }.buttonStyle(GeneralTextButtonStyle())
                }
                GeneralRow("Import settings", detail: "Restore a Moku iOS settings file.") {
                    Button("Import") { importKind = "settings"; importing = true }.buttonStyle(GeneralTextButtonStyle())
                }
            }
            GeneralSection("Preferences") {
                GeneralRow("Reset preferences", detail: "Keep saved titles, files, history, and app lock.") {
                    Button("Reset") { confirmation = .resetPreferences }.buttonStyle(GeneralTextButtonStyle())
                }
            }
            if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(GeneralStyle.faint) }
        }.disabled(model.busy || server.saving)
            .task { await model.load(); await server.load() }
            .fileExporter(isPresented: $exporting, document: document, contentType: exportName.hasSuffix(".json") ? .json : .data, defaultFilename: exportName) { result in
                if case .failure = result { model.notice = "Couldn’t export this file." }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: (importKind == "Mihon backup" || importKind == "local file") ? [.data] : [.json]) { result in
                if case .success(let url) = result { pendingImport = url }
                if case .failure = result { model.notice = "Couldn’t open this file." }
            }
            .confirmationDialog("Import \(importKind)?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
                Button("Import") { if let url = pendingImport { Task { await importFile(url) } } }
            }
            .confirmationDialog("Confirm storage action", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
                Button("Continue", role: .destructive) { if let action = confirmation { Task { await perform(action) } } }
            } message: { Text(confirmationMessage) }
    }
    private func validComponent(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\") }
    private var validDirectoryName: Bool { validComponent(path) }
    private var confirmationMessage: String {
        switch confirmation {
        case .clear(_, let label): "Clear \(label)? This removes the category’s files."
        case .deleteBackup(let name): "Delete \(name)?"
        case .importBackup(let name): "Merge titles and reading progress from \(name)?"
        case .convert: "Convert existing manga downloads to the selected format?"
        case .relocate: "Change the downloads directory?"
        case .relocateLocal: "Move existing local media to the new directory?"
        case .resetPreferences: "Restore default app preferences?"
        case nil: ""
        }
    }
    private func value(_ title: String, _ value: String) -> some View {
        GeneralRow(title, detail: "") { Text(value).font(.subheadline).foregroundStyle(GeneralStyle.text).multilineTextAlignment(.trailing).frame(maxWidth: 160).fixedSize(horizontal: false, vertical: true) }
    }
    private func bytes(_ value: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(max(0, min(value, Double(Int64.max / 2)))), countStyle: .file) }
    private func exportSettings() {
        do { document = SettingsExportDocument(data: try JSONEncoder().encode(SettingsArchive(defaults: appData.preferences))); exportName = "Moku-settings.json"; exporting = true }
        catch { model.notice = "Couldn’t export settings." }
    }
    private func exportLibrary() {
        do { document = SettingsExportDocument(data: try JSONEncoder().encode(library.entries)); exportName = "Moku-library.json"; exporting = true }
        catch { model.notice = "Couldn’t export library." }
    }
    private func importFile(_ url: URL) async {
        defer { pendingImport = nil }
        if importKind == "local file" {
            model.busy = true
            defer { model.busy = false }
            do {
                try await Backend.shared.importLocalFile(url, kind: localKind, series: localSeries, chapter: localChapter)
                await BackendAPI.shared.clearContentCache()
                model.notice = "Local file imported."
            } catch { model.notice = "Couldn’t import this local file. Check its format and choose a name that is not already in use." }
            return
        }
        if importKind == "Mihon backup" {
            await importMihonFile(url)
            return
        }
        if importKind == "library" { if !(await library.importLibrary(from: url)) { model.notice = library.error }; return }
        do {
            let values = try await Task.detached {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                return try JSONDecoder().decode(SettingsArchive.self, from: Data(contentsOf: url))
            }.value.validatedValues()
            for (key, value) in values { appData.preferences.set(value, forKey: key) }
            if let raw = values["reader.preferences.v1"] as? Data { reader.document = try JSONDecoder().decode(ReaderPreferenceDocument.self, from: raw) }
            model.notice = "Settings imported."
        } catch { model.notice = "Couldn’t import settings. Choose a valid Moku iOS settings file." }
    }
    private func importMihonFile(_ url: URL) async {
        guard !model.busy else { return }
        model.busy = true
        defer { model.busy = false }
        do {
            let data = try await Task.detached {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard url.pathExtension.lowercased() == "tachibk",
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                    size > 0, size <= 64 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
                return try Data(contentsOf: url)
            }.value
            let boundary = "Moku-" + UUID().uuidString
            var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"library.tachibk\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
            body.append(data)
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            let response = try await BackendAPI.shared.api(path: "/api/backups/import-file", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
            struct Result: Decodable { let mangaImported: Int; let mangaSkipped: Int; let warnings: [String]? }
            let result = try JSONDecoder().decode(Result.self, from: response)
            model.notice = "Imported \(result.mangaImported) titles; skipped \(result.mangaSkipped)." + (result.warnings?.isEmpty == false ? " " + result.warnings!.joined(separator: " ") : "")
            await BackendAPI.shared.clearContentCache()
            _ = await library.refreshFromServer()
        } catch { model.notice = "Couldn’t import this Mihon backup." }
    }
    private func perform(_ action: StorageAction) async {
        confirmation = nil
        switch action {
        case .clear(let key, _):
            if await model.run("clearStorageCategory(key: \(BackendAPI.literal(key))) { usedBytes }") { await BackendAPI.shared.clearContentCache() }
        case .deleteBackup(let name): await model.run("deleteDatabaseBackup(name: \(BackendAPI.literal(name)))")
        case .importBackup(let name):
            if await model.run("importMihonBackup(name: \(BackendAPI.literal(name))) { mangaImported mangaSkipped warnings }") { _ = await library.refreshFromServer() }
        case .convert:
            let format = server.values.first { $0.key == "manga_download_format" }?.value ?? "loose"
            await model.run("migrateMangaDownloadFormat(target: \(BackendAPI.literal(format))) { chaptersMigrated chaptersFailed }")
        case .relocate:
            guard validDirectoryName else { return }
            guard let directory = model.info?.dataDir else { return }
            let target = URL(fileURLWithPath: directory).appending(path: path, directoryHint: .isDirectory).path
            await model.run("relocateDownloads(newPath: \(BackendAPI.literal(target)), migrate: \(migrate)) { newPath movedFiles }")
            await server.load()
        case .relocateLocal:
            guard validComponent(localPath), let directory = model.info?.dataDir else { return }
            let target = URL(fileURLWithPath: directory).appending(path: localPath, directoryHint: .isDirectory).path
            await model.run("relocateLocalSource(newPath: \(BackendAPI.literal(target)), migrate: true) { newPath movedFiles }")
            await server.load()
        case .resetPreferences:
            for key in appData.preferences.dictionaryRepresentation().keys where SettingsArchive.permitted(key) && key != "reader.preferences.v1" { appData.preferences.removeObject(forKey: key) }
            reader.document.global = MangaReadingSettings()
            reader.document.behaviour = ReaderBehaviour()
            model.notice = "Preferences reset."
        }
    }
}
private extension String { var nonempty: String? { isEmpty ? nil : self } }

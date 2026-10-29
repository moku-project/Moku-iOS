import Foundation
import Observation

extension Notification.Name {
    static let contentVisibilityDidChange = Notification.Name("contentVisibilityDidChange")
}

@MainActor @Observable
final class LibraryStore {
    private(set) var entries: [MediaEntry] = [] {
        didSet { entryIDs = Set(entries.map(\.id)); entriesRevision &+= 1 }
    }
    private(set) var entriesRevision = 0
    private var entryIDs: Set<String> = []
    @ObservationIgnored private var refreshedAt: Date?
    private(set) var loaded = false
    private(set) var serverVisibleIDs: Set<String>?
    private(set) var visibilityRevision = 0
    private(set) var busy = false
    var error: String?
    private(set) var organization = LibraryOrganization()
    private var organizationLoaded = false
    private var organizationBusy = false
    private let organizationDocument: StoredDocument<LibraryOrganization>
    private let migrationDocument: StoredDocument<Bool>
    private let document: StoredDocument<[MediaEntry]>
    private let synchronizeWithServer: Bool
    private var loading: Task<[MediaEntry]?, Error>?

    init(directory: URL, synchronizeWithServer: Bool = false) {
        self.synchronizeWithServer = synchronizeWithServer
        migrationDocument = StoredDocument(url: directory.appending(path: "library-server-migrated.json"))
        document = StoredDocument(url: directory.appending(path: "library.json"))
        organizationDocument = StoredDocument(
            url: directory.appending(path: "library-organization.json"))
    }

    func load() async {
        guard !loaded else { return }
        if loading == nil { loading = Task { try await document.read() } }
        do {
            let saved = try await loading?.value
            guard !loaded else { return }
            entries = saved ?? []
            loaded = true
            error = nil
        } catch {
            self.error = "Couldn’t load your library."
            loading = nil
        }
    }

    /// Merge server imports with device-only entries without removing local saves.
    func refreshFromServer(ifStale: Bool = false) async -> Bool {
        guard synchronizeWithServer else { return true }
        await load()
        guard loaded else { return false }
        // A settings change can arrive while an older visibility query is running.
        while busy {
            do { try await Task.sleep(for: .milliseconds(25)) }
            catch { return false }
        }
        guard !Task.isCancelled else { return false }
        if ifStale, let refreshedAt, Date.now.timeIntervalSince(refreshedAt) < 30 { return true }
        let revision = visibilityRevision
        busy = true
        defer { busy = false }
        struct Record: Decodable, Sendable {
            let id: String; let title: String; let contentType: String
            let sourceName: String; let thumbnailUrl: String?
            let extensionId: String?; let externalId: String
            var entry: MediaEntry {
                MediaEntry(id: id, title: title, media: contentType == "ANIME" ? .anime : contentType == "NOVEL" ? .novels : .manga, sourceName: sourceName, coverURL: BackendAPI.coverURL(thumbnailUrl), extensionID: extensionId, externalID: externalId)
            }
        }
        struct Response: Decodable, Sendable {
            struct Page: Decodable, Sendable { let items: [Record]; let hasMore: Bool }
            let library: Page
        }
        do {
            var migrationFailed = false
            if try await migrationDocument.read() != true {
                for entry in entries where Int64(entry.id) != nil {
                    do {
                        _ = try await LiveMediaRepository.shared.setSaved(true, id: entry.id)
                    } catch {
                        migrationFailed = true
                    }
                }
                if !migrationFailed { try await migrationDocument.write(true) }
            }
            var imported: [MediaEntry] = []
            var offset = 0
            while true {
                let response: Response = try await BackendAPI.shared.graphql("{ library(limit: 100, offset: \(offset)) { items { id title contentType sourceName thumbnailUrl extensionId externalId } hasMore } }", requiresSourceRuntime: false)
                imported += response.library.items.map(\.entry)
                guard response.library.hasMore, !response.library.items.isEmpty else { break }
                offset += response.library.items.count
            }
            try Task.checkCancellation()
            guard revision == visibilityRevision else { return false }
            let ids = Set(imported.map(\.id))
            if serverVisibleIDs != ids { serverVisibleIDs = ids }
            let merged = entries.filter { !ids.contains($0.id) } + imported
            if entries != merged {
                try await document.write(merged)
                entries = merged
            }
            refreshedAt = migrationFailed || revision != visibilityRevision ? nil : .now
            error = migrationFailed ? "Some saved titles couldn’t sync. Retry to restore them to the server library." : nil
            return true
        } catch {
            if !Task.isCancelled { self.error = "Couldn’t refresh the server library." }
            return false
        }
    }

    func invalidateServerVisibility() {
        refreshedAt = nil
        visibilityRevision &+= 1
    }

    func autoLink(_ entry: MediaEntry) async {
        await loadOrganization()
        let key = Self.titleKey(entry.title)
        guard !key.isEmpty else { return }
        let matches = entries.filter { $0.media == entry.media && Self.titleKey($0.title) == key }
        guard matches.contains(where: { $0.id != entry.id }) else { return }
        var next = organization
        var links = next.linkedTitles ?? [:]
        let ids = Set(matches.map(\.id) + [entry.id])
        for id in ids { links[id] = ids.subtracting([id]) }
        next.linkedTitles = links
        _ = await saveOrganization(next)
    }

    /// Desktop "Series link": links or unlinks two titles as the same series,
    /// in both directions.
    func setLinked(_ id: String, _ other: String, linked: Bool) async {
        await loadOrganization()
        guard id != other else { return }
        var next = organization
        var links = next.linkedTitles ?? [:]
        if linked {
            links[id, default: []].insert(other)
            links[other, default: []].insert(id)
        } else {
            links[id]?.remove(other)
            links[other]?.remove(id)
        }
        next.linkedTitles = links.filter { !$0.value.isEmpty }
        _ = await saveOrganization(next)
    }

    func linkedEntries(for id: String) -> [MediaEntry] {
        let ids = organization.linkedTitles?[id] ?? []
        return entries.filter { ids.contains($0.id) }
    }

    private static func titleKey(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    func loadOrganization() async {
        guard !organizationLoaded else { return }
        do {
            let saved = try await organizationDocument.read()
            guard !organizationLoaded else { return }
            organization = saved ?? LibraryOrganization()
            organizationLoaded = true
        } catch { self.error = "Couldn’t load folders and stars." }
    }

    @discardableResult
    func saveOrganization(_ proposed: LibraryOrganization) async -> Bool {
        guard organizationLoaded, !organizationBusy else { return false }
        organizationBusy = true
        defer { organizationBusy = false }
        do {
            var next = proposed
            if synchronizeWithServer { next = try await synchronizeFolders(next) }
            try await organizationDocument.write(next)
            organization = next
            error = nil
            return true
        } catch {
            self.error = "Couldn’t save folders and stars."
            return false
        }
    }

    private func synchronizeFolders(_ proposed: LibraryOrganization) async throws -> LibraryOrganization {
        var next = proposed
        func mutate(_ value: String) async throws {
            let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql("mutation { \(value) }", requiresSourceRuntime: false)
        }
        for index in next.folders.indices {
            var folder = next.folders[index]
            let old = organization.folders.first { $0.id == folder.id }
            if folder.serverID == nil {
                struct Result: Decodable, Sendable { struct Folder: Decodable, Sendable { let id: String }; let createFolder: Folder }
                let result: Result = try await BackendAPI.shared.graphql("mutation { createFolder(name: \(BackendAPI.literal(folder.name))) { id } }", requiresSourceRuntime: false)
                folder.serverID = result.createFolder.id
                next.folders[index] = folder
                // Save the assigned ID before subsequent requests so retries cannot create duplicates.
                var checkpoint = organization
                if let i = checkpoint.folders.firstIndex(where: { $0.id == folder.id }) { checkpoint.folders[i].serverID = folder.serverID }
                else { var item = folder; item.entryIDs = []; checkpoint.folders.append(item) }
                try await organizationDocument.write(checkpoint)
                organization = checkpoint
            }
            guard let serverID = folder.serverID else { continue }
            let id = BackendAPI.literal(serverID)
            if old?.name != folder.name { try await mutate("renameFolder(folderId: \(id), name: \(BackendAPI.literal(folder.name))) { id }") }
            // Starring a title saves organization too; only send what changed.
            if old == nil || old?.includeInUpdate != folder.includeInUpdate || old?.includeInDownload != folder.includeInDownload {
                try await mutate("updateFolderFlags(folderId: \(id), includeInUpdate: \(folder.includeInUpdate ?? true), includeInDownload: \(folder.includeInDownload ?? true)) { id }")
            }
            // Tsunagu 0.6.0 stores content types per folder, as desktop does; empty means all.
            if (old?.contentTypes ?? []) != (folder.contentTypes ?? []) {
                let types = (folder.contentTypes ?? []).map(\.graphQLType).joined(separator: ", ")
                try await mutate("setFolderContentTypes(folderId: \(id), contentTypes: [\(types)]) { id }")
            }
            if old == nil || organization.folders.firstIndex(where: { $0.id == folder.id }) != index {
                try await mutate("reorderFolder(folderId: \(id), sortOrder: \(index)) { id }")
            }
            let before = old?.entryIDs ?? []
            for entry in folder.entryIDs.subtracting(before) where Int64(entry) != nil {
                try await mutate("addMediaToFolder(mediaId: \(BackendAPI.literal(entry)), folderId: \(id))")
            }
            for entry in before.subtracting(folder.entryIDs) where Int64(entry) != nil {
                try await mutate("removeMediaFromFolder(mediaId: \(BackendAPI.literal(entry)), folderId: \(id))")
            }
        }
        let kept = Set(next.folders.map(\.id))
        for folder in organization.folders where !kept.contains(folder.id) {
            if let id = folder.serverID { try await mutate("deleteFolder(folderId: \(BackendAPI.literal(id)))") }
        }
        return next
    }

    func importLibrary(from url: URL) async -> Bool {
        await load()
        guard loaded, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let imported = try await Task.detached {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                return try JSONDecoder().decode([MediaEntry].self, from: Data(contentsOf: url))
            }.value
            var next = entries
            var known = Set(entries.map(\.id))
            var addedIDs = Set<String>()
            for entry in imported where !entry.id.isEmpty && !entry.title.isEmpty {
                if known.insert(entry.id).inserted {
                    if synchronizeWithServer, Int64(entry.id) != nil { _ = try await LiveMediaRepository.shared.setSaved(true, id: entry.id) }
                    next.append(entry)
                    addedIDs.insert(entry.id)
                }
            }
            try await document.write(next)
            entries = next
            serverVisibleIDs?.formUnion(addedIDs)
            error = nil
            return true
        } catch {
            self.error = "Couldn’t import this file. Choose a Moku library JSON file."
            return false
        }
    }

    func contains(_ entry: MediaEntry) -> Bool { entryIDs.contains(entry.id) }

    @discardableResult func setSaved(_ saved: Bool, entry: MediaEntry) async -> Bool {
        await load()
        guard loaded else { return false }
        // A background refresh must not silently drop an explicit save/remove.
        while busy {
            do { try await Task.sleep(for: .milliseconds(25)) }
            catch { return false }
        }
        guard !Task.isCancelled else { return false }
        busy = true
        defer { busy = false }
        var next = entries.filter { $0.id != entry.id }
        if saved { next.append(entry) }
        do {
            if synchronizeWithServer, Int64(entry.id) != nil {
                _ = try await LiveMediaRepository.shared.setSaved(saved, id: entry.id)
            }
            try await document.write(next)
            entries = next
            if saved { serverVisibleIDs?.insert(entry.id) } else { serverVisibleIDs?.remove(entry.id) }
            error = nil
            return true
        } catch {
            self.error = "Couldn’t save your library."
            return false
        }
    }
}

import Foundation
import Observation

/// Two-way sync between this phone's embedded server and a paired desktop.
///
/// - Titles match across devices by extension package plus the source's
///   external ID (database IDs differ per device).
/// - Library membership is a 3-way merge against the titles both sides had at
///   the last sync, so a removal on either device carries over instead of
///   coming back. A title missing from one side's list is only removed once
///   that side confirms `inLibrary: false`: the content filter also hides
///   titles from lists, and a stricter level must never delete anything.
/// - Reading progress matches chapters by external ID; the newer `updatedAt`
///   wins and is written to the other side.
/// - Folders sync by name and only ever add membership.
@MainActor @Observable final class DesktopSync {
    static let shared = DesktopSync()

    struct Report: Codable, Equatable, Sendable {
        var finishedAt: Date
        var addedToPhone = 0
        var addedToDesktop = 0
        var removedFromPhone = 0
        var removedFromDesktop = 0
        var progressUpdated = 0
        var foldersUpdated = 0
        var missingOnPhone: [String: Int] = [:]
        var missingOnDesktop: [String: Int] = [:]
        var failures = 0

        var summary: String {
            var parts: [String] = []
            let added = addedToPhone + addedToDesktop
            if added > 0 { parts.append("\(added) title\(added == 1 ? "" : "s") added") }
            let removed = removedFromPhone + removedFromDesktop
            if removed > 0 { parts.append("\(removed) removed") }
            if progressUpdated > 0 { parts.append("\(progressUpdated) chapter\(progressUpdated == 1 ? "" : "s") of progress") }
            if foldersUpdated > 0 { parts.append("\(foldersUpdated) folder change\(foldersUpdated == 1 ? "" : "s")") }
            return parts.isEmpty ? "Everything was already in sync." : parts.joined(separator: " · ")
        }
    }

    /// The same title's media ID on each device, as of the last sync.
    private struct Pair: Codable, Equatable {
        var phone: String
        var desktop: String
    }

    private struct Snapshot: Codable {
        var pairs: [String: Pair] = [:]
        var syncedAt: Date?
        var report: Report?
    }

    private(set) var pairing: DesktopPairing?
    private(set) var syncing = false
    private(set) var phase = ""
    private(set) var lastReport: Report?
    private(set) var lastError: String?
    @ObservationIgnored private var snapshot = Snapshot()
    @ObservationIgnored private let document = StoredDocument<Snapshot>(
        url: URL.applicationSupportDirectory.appending(path: "Moku/desktop-sync.json"))
    @ObservationIgnored private var loaded = false

    var isPaired: Bool { pairing != nil }
    var lastSyncedAt: Date? { lastReport?.finishedAt }

    func load() async {
        guard !loaded else { return }
        loaded = true
        pairing = DesktopPairingStore.load()
        snapshot = (try? await document.read()) ?? Snapshot()
        lastReport = snapshot.report
    }

    func connect(_ pairing: DesktopPairing) async {
        DesktopPairingStore.save(pairing)
        self.pairing = pairing
        // A different desktop has a different history; start the merge fresh.
        snapshot = Snapshot()
        lastReport = nil
        lastError = nil
        try? await document.write(snapshot)
    }

    func disconnect() async {
        DesktopPairingStore.clear()
        pairing = nil
        snapshot = Snapshot()
        lastReport = nil
        lastError = nil
        try? await document.write(snapshot)
    }

    /// Foreground trigger: at most every five minutes, and silent on failure
    /// (the desktop may simply be asleep or on another network).
    func syncIfDue(library: LibraryStore) async {
        await load()
        guard isPaired, !syncing else { return }
        if let last = snapshot.syncedAt, Date.now.timeIntervalSince(last) < 300 { return }
        await sync(library: library, announce: false)
    }

    func sync(library: LibraryStore, announce: Bool = true) async {
        await load()
        guard let pairing, !syncing else { return }
        syncing = true
        lastError = nil
        defer { syncing = false; phase = "" }
        let remote = DesktopClient(pairing: pairing)
        do {
            var report = Report(finishedAt: .now)
            phase = "Reading libraries"
            let known = snapshot.pairs
            async let localSide = Self.side(remote: nil, known: Set(known.values.map(\.phone)))
            async let remoteSide = Self.side(remote: remote, known: Set(known.values.map(\.desktop)))
            let (phone, desktop) = try await (localSide, remoteSide)

            phase = "Merging library"
            let linked = try await mergeLibrary(phone: phone, desktop: desktop, remote: remote, library: library, report: &report)

            phase = "Syncing progress"
            // Re-read both sides so newly added titles have IDs and chapters.
            let (phoneNow, desktopNow) = try await (
                Self.side(remote: nil, known: Set(linked.values.map(\.phone))),
                Self.side(remote: remote, known: Set(linked.values.map(\.desktop))))
            var pairs = linked
            for (key, mine) in phoneNow.items {
                if let theirs = desktopNow.items[key] { pairs[key] = Pair(phone: mine.id, desktop: theirs.id) }
            }
            try await mergeProgress(
                phone: phoneNow, desktop: desktopNow, remote: remote,
                newlyPaired: Set(pairs.keys).subtracting(known.keys), report: &report)

            phase = "Syncing folders"
            await mergeFolders(phone: phoneNow, desktop: desktopNow, remote: remote, library: library, report: &report)

            report.finishedAt = .now
            snapshot.pairs = pairs
            snapshot.syncedAt = .now
            snapshot.report = report
            try? await document.write(snapshot)
            lastReport = report
            let refreshed = await remote.pairing
            if refreshed != pairing { self.pairing = refreshed }
            if announce || report.summary != "Everything was already in sync." {
                Toaster.shared.show("Synced with \(pairing.name)", detail: report.summary, kind: .info)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Sync failed. Try again."
            lastError = message
            if announce { Toaster.shared.show("Sync failed", detail: message, kind: .error) }
        }
    }

    // MARK: - Reading each side

    struct Item: Sendable {
        let id: String
        let key: String
        let package: String
        let externalID: String
        let title: String
        let folders: [String]
        let progress: [Progress]
    }

    struct Progress: Decodable, Sendable {
        let chapterId: String
        let progress: Double
        let completed: Bool
        let positionSeconds: Double?
        let durationSeconds: Double?
        let updatedAt: String
        var date: Date { DesktopSync.date(updatedAt) ?? .distantPast }
    }

    struct Side: Sendable {
        /// packageName → extension id on that device (installed only).
        let extensions: [String: String]
        let items: [String: Item]
    }

    /// Lists the library, then reads `known` paired titles the list left out:
    /// the content filter hides titles from `library`, never from `media(id:)`.
    private nonisolated static func side(remote: DesktopClient?, known: Set<String>) async throws -> Side {
        struct Extensions: Decodable, Sendable {
            struct Item: Decodable, Sendable { let id: String; let packageName: String }
            let installedExtensions: [Item]
        }
        struct Library: Decodable, Sendable {
            struct Folder: Decodable, Sendable { let name: String; let systemKey: String? }
            struct Media: Decodable, Sendable {
                let id: String; let extensionId: String?; let externalId: String; let title: String
                var inLibrary: Bool? = nil
                let folders: [Folder]; let readingProgress: [Progress]
            }
            struct Page: Decodable, Sendable { let items: [Media]; let hasMore: Bool }
            let library: Page
        }
        func query<T: Decodable & Sendable>(_ text: String) async throws -> T {
            if let remote { return try await remote.graphql(text) }
            return try await BackendAPI.shared.graphql(text, refresh: true, requiresSourceRuntime: false)
        }
        let installed: Extensions = try await query("{ installedExtensions { id packageName } }")
        let packages = Dictionary(installed.installedExtensions.map { ($0.id, $0.packageName) }, uniquingKeysWith: { a, _ in a })
        var items: [String: Item] = [:]
        var listed = Set<String>()
        func insert(_ media: Library.Media) {
            listed.insert(media.id)
            // Local-source titles have no extension and stay device-only.
            guard let extensionID = media.extensionId, let package = packages[extensionID] else { return }
            let key = "\(package)|\(media.externalId)"
            items[key] = Item(
                id: media.id, key: key, package: package, externalID: media.externalId, title: media.title,
                folders: media.folders.filter { $0.systemKey == nil }.map(\.name), progress: media.readingProgress)
        }
        let fields = "id extensionId externalId title folders { name systemKey } readingProgress { chapterId progress completed positionSeconds durationSeconds updatedAt }"
        var offset = 0
        while true {
            let page: Library = try await query("{ library(limit: 200, offset: \(offset)) { items { \(fields) } hasMore } }")
            page.library.items.forEach(insert)
            guard page.library.hasMore, !page.library.items.isEmpty else { break }
            offset += page.library.items.count
        }
        struct Single: Decodable, Sendable { let media: Library.Media? }
        for id in known.subtracting(listed) {
            let single: Single = try await query("{ media(id: \(BackendAPI.literal(id))) { \(fields) inLibrary } }")
            if let media = single.media, media.inLibrary == true { insert(media) }
        }
        return Side(extensions: Dictionary(packages.map { ($1, $0) }, uniquingKeysWith: { a, _ in a }), items: items)
    }

    // MARK: - Library

    /// Returns pairs known after the merge: kept ones and newly added ones, so
    /// later steps and the next sync can read them even if a list hides them.
    private func mergeLibrary(
        phone: Side, desktop: Side, remote: DesktopClient, library: LibraryStore, report: inout Report
    ) async throws -> [String: Pair] {
        let previous = snapshot.pairs
        var retained: [String: Pair] = [:]
        var phoneChanged = false

        for (key, item) in phone.items where desktop.items[key] == nil {
            if let pair = previous[key] {
                // Known on the desktop at the last sync; remove only if it says so.
                switch try await Self.stillSaved(id: pair.desktop, run: { try await remote.graphql($0) }) {
                case false:
                    if let entry = library.entries.first(where: { $0.id == item.id }),
                        await library.setSaved(false, entry: entry)
                    {
                        report.removedFromPhone += 1
                    } else { report.failures += 1 }
                case true:
                    retained[key] = pair
                }
                continue
            }
            guard let extensionID = desktop.extensions[item.package] else {
                report.missingOnDesktop[item.package, default: 0] += 1
                continue
            }
            do {
                let result = try await Self.add(externalID: item.externalID, extensionID: extensionID) { try await remote.graphql($0) }
                retained[key] = Pair(phone: item.id, desktop: result.id)
                if result.added { report.addedToDesktop += 1 }
            } catch { report.failures += 1 }
        }

        for (key, item) in desktop.items where phone.items[key] == nil {
            if let pair = previous[key] {
                let saved = try await Self.stillSaved(id: pair.phone) {
                    try await BackendAPI.shared.graphql($0, refresh: true, requiresSourceRuntime: false)
                }
                if saved {
                    retained[key] = pair
                } else {
                    do {
                        let _: IgnoredGraphQLResult = try await remote.graphql(
                            "mutation { setInLibrary(mediaId: \(BackendAPI.literal(item.id)), inLibrary: false) { id } }")
                        report.removedFromDesktop += 1
                    } catch { report.failures += 1 }
                }
                continue
            }
            guard let extensionID = phone.extensions[item.package] else {
                report.missingOnPhone[item.package, default: 0] += 1
                continue
            }
            do {
                let result = try await Self.add(externalID: item.externalID, extensionID: extensionID) {
                    try await BackendAPI.shared.graphql($0, requiresSourceRuntime: true)
                }
                retained[key] = Pair(phone: result.id, desktop: item.id)
                if result.added {
                    report.addedToPhone += 1
                    phoneChanged = true
                }
            } catch { report.failures += 1 }
        }

        if phoneChanged {
            library.invalidateServerVisibility()
            _ = await library.refreshFromServer()
        }
        return retained
    }

    /// Whether a title is still saved on that device. A missing row counts as removed.
    private nonisolated static func stillSaved(
        id: String, run: @Sendable (String) async throws -> SavedState
    ) async throws -> Bool {
        let result = try await run("{ media(id: \(BackendAPI.literal(id))) { inLibrary } }")
        return result.media?.inLibrary ?? false
    }

    struct SavedState: Decodable, Sendable {
        struct Media: Decodable, Sendable { let inLibrary: Bool }
        let media: Media?
    }

    /// `resolveMedia` creates the title (and its chapters) on that device first.
    private nonisolated static func add(
        externalID: String, extensionID: String,
        run: @Sendable (String) async throws -> IgnoredGraphQLResultHolder
    ) async throws -> (id: String, added: Bool) {
        let holder = try await run(
            "{ resolveMedia(extensionId: \(BackendAPI.literal(extensionID)), externalId: \(BackendAPI.literal(externalID)), syncChapters: true) { id inLibrary } }")
        guard let id = holder.resolvedID else { throw DesktopSyncError.server("Couldn’t resolve the title.") }
        // Already saved but hidden from that side's list by its content level.
        if holder.inLibrary { return (id, false) }
        _ = try await run("mutation { setInLibrary(mediaId: \(BackendAPI.literal(id)), inLibrary: true) { id } }")
        return (id, true)
    }

    // MARK: - Progress

    private func mergeProgress(
        phone: Side, desktop: Side, remote: DesktopClient, newlyPaired: Set<String>, report: inout Report
    ) async throws {
        let since = snapshot.syncedAt ?? .distantPast
        for (key, mine) in phone.items {
            guard let theirs = desktop.items[key] else { continue }
            // A new pair merges everything; older pairs only what changed since.
            let changed = newlyPaired.contains(key) || (mine.progress + theirs.progress).contains { $0.date > since }
            guard changed, !(mine.progress.isEmpty && theirs.progress.isEmpty) else { continue }
            do {
                async let phoneChapters = Self.chapterIDs(mediaID: mine.id) {
                    try await BackendAPI.shared.graphql($0, refresh: true, requiresSourceRuntime: false)
                }
                async let desktopChapters = Self.chapterIDs(mediaID: theirs.id) { try await remote.graphql($0) }
                let (phoneMap, desktopMap) = try await (phoneChapters, desktopChapters)
                let phoneByExternal = Dictionary(mine.progress.compactMap { p in phoneMap[p.chapterId].map { ($0, p) } }, uniquingKeysWith: { a, _ in a })
                let desktopByExternal = Dictionary(theirs.progress.compactMap { p in desktopMap[p.chapterId].map { ($0, p) } }, uniquingKeysWith: { a, _ in a })
                let phoneIDs = Dictionary(phoneMap.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
                let desktopIDs = Dictionary(desktopMap.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })

                for external in Set(phoneByExternal.keys).union(desktopByExternal.keys) {
                    let a = phoneByExternal[external], b = desktopByExternal[external]
                    let newer: Progress
                    let writeToDesktop: Bool
                    switch (a, b) {
                    case let (a?, b?):
                        guard Self.differs(a, b) else { continue }
                        writeToDesktop = a.date >= b.date
                        newer = writeToDesktop ? a : b
                    case let (a?, nil): newer = a; writeToDesktop = true
                    case let (nil, b?): newer = b; writeToDesktop = false
                    default: continue
                    }
                    let mutation = { (mediaID: String, chapterID: String) in
                        """
                        mutation { updateReadingProgress(mediaId: \(BackendAPI.literal(mediaID)), chapterId: \(BackendAPI.literal(chapterID)),
                        progress: \(newer.progress), completed: \(newer.completed)\(newer.positionSeconds.map { ", positionSeconds: \($0)" } ?? "")\(newer.durationSeconds.map { ", durationSeconds: \($0)" } ?? "")) { id } }
                        """
                    }
                    if writeToDesktop {
                        guard let chapterID = desktopIDs[external] else { continue }
                        let _: IgnoredGraphQLResult = try await remote.graphql(mutation(theirs.id, chapterID))
                    } else {
                        guard let chapterID = phoneIDs[external] else { continue }
                        let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                            mutation(mine.id, chapterID), requiresSourceRuntime: false)
                    }
                    report.progressUpdated += 1
                }
            } catch let error as DesktopSyncError where error == .unreachable {
                throw error
            } catch { report.failures += 1 }
        }
    }

    private nonisolated static func differs(_ a: Progress, _ b: Progress) -> Bool {
        a.completed != b.completed || abs(a.progress - b.progress) > 0.01
            || abs((a.positionSeconds ?? 0) - (b.positionSeconds ?? 0)) > 5
    }

    /// chapter id → external id for one title.
    private nonisolated static func chapterIDs(
        mediaID: String, run: @Sendable (String) async throws -> ChapterIDs
    ) async throws -> [String: String] {
        let result = try await run("{ media(id: \(BackendAPI.literal(mediaID))) { chapters { id externalId } } }")
        return Dictionary((result.media?.chapters ?? []).map { ($0.id, $0.externalId) }, uniquingKeysWith: { a, _ in a })
    }

    struct ChapterIDs: Decodable, Sendable {
        struct Media: Decodable, Sendable {
            struct Chapter: Decodable, Sendable { let id: String; let externalId: String }
            let chapters: [Chapter]
        }
        let media: Media?
    }

    // MARK: - Folders

    private func mergeFolders(
        phone: Side, desktop: Side, remote: DesktopClient, library: LibraryStore, report: inout Report
    ) async {
        await library.loadOrganization()
        // Phone: folder name → titles that should be in it (from the desktop).
        var next = library.organization
        var phoneChanged = false
        for (key, theirs) in desktop.items {
            guard let mine = phone.items[key] else { continue }
            for name in Set(theirs.folders).subtracting(mine.folders) {
                if let index = next.folders.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    if next.folders[index].entryIDs.insert(mine.id).inserted { phoneChanged = true; report.foldersUpdated += 1 }
                } else {
                    var folder = LibraryFolder(name: name)
                    folder.entryIDs = [mine.id]
                    next.folders.append(folder)
                    phoneChanged = true
                    report.foldersUpdated += 1
                }
            }
        }
        if phoneChanged, !(await library.saveOrganization(next)) { report.failures += 1 }

        // Desktop: create missing folders by name, then add membership.
        struct Folders: Decodable, Sendable { struct Folder: Decodable, Sendable { let id: String; let name: String }; let folders: [Folder] }
        guard let existing: Folders = try? await remote.graphql("{ folders { id name } }") else { return }
        var ids = Dictionary(existing.folders.map { ($0.name.lowercased(), $0.id) }, uniquingKeysWith: { a, _ in a })
        for (key, mine) in phone.items {
            guard let theirs = desktop.items[key] else { continue }
            for name in Set(mine.folders).subtracting(theirs.folders) {
                do {
                    if ids[name.lowercased()] == nil {
                        struct Created: Decodable, Sendable { struct Folder: Decodable, Sendable { let id: String }; let createFolder: Folder }
                        let created: Created = try await remote.graphql("mutation { createFolder(name: \(BackendAPI.literal(name))) { id } }")
                        ids[name.lowercased()] = created.createFolder.id
                    }
                    guard let folderID = ids[name.lowercased()] else { continue }
                    let _: IgnoredGraphQLResult = try await remote.graphql(
                        "mutation { addMediaToFolder(mediaId: \(BackendAPI.literal(theirs.id)), folderId: \(BackendAPI.literal(folderID))) }")
                    report.foldersUpdated += 1
                } catch { report.failures += 1 }
            }
        }
    }

    nonisolated static func date(_ value: String) -> Date? {
        (try? Date(value, strategy: .iso8601))
            ?? (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }
}

/// Decodes either a `resolveMedia` or a mutation result, so `add` can use one
/// runner for both the phone and the desktop.
struct IgnoredGraphQLResultHolder: Decodable, Sendable {
    let resolvedID: String?
    let inLibrary: Bool
    private enum CodingKeys: String, CodingKey { case resolveMedia }
    private struct Media: Decodable { let id: String; let inLibrary: Bool? }
    init(from decoder: any Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        let media = try? container?.decodeIfPresent(Media.self, forKey: .resolveMedia)
        resolvedID = media?.id
        inLibrary = media?.inLibrary ?? false
    }
}

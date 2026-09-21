import Foundation
import Observation

@MainActor @Observable
final class ProfileLibrary {
    private(set) var entries: [MediaEntry] = []
    private(set) var loaded = false
    private(set) var busy = false
    var error: String?
    private(set) var organization = LibraryOrganization()
    private var organizationLoaded = false
    private var organizationBusy = false
    private let organizationDocument: ProfileDocument<LibraryOrganization>
    private let document: ProfileDocument<[MediaEntry]>
    private var loading: Task<[MediaEntry]?, Error>?

    init(directory: URL) {
        document = ProfileDocument(url: directory.appending(path: "library.json"))
        organizationDocument = ProfileDocument(
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
            self.error = "Couldn’t load this profile’s library."
            loading = nil
        }
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
    func saveOrganization(_ next: LibraryOrganization) async -> Bool {
        guard organizationLoaded, !organizationBusy else { return false }
        organizationBusy = true
        defer { organizationBusy = false }
        do {
            try await organizationDocument.write(next)
            organization = next
            error = nil
            return true
        } catch {
            self.error = "Couldn’t save folders and stars."
            return false
        }
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
            for entry in imported where !entry.id.isEmpty && !entry.title.isEmpty {
                if known.insert(entry.id).inserted { next.append(entry) }
            }
            try await document.write(next)
            entries = next
            error = nil
            return true
        } catch {
            self.error = "Couldn’t import this file. Choose a Moku library JSON file."
            return false
        }
    }

    func contains(_ entry: MediaEntry) -> Bool { entries.contains { $0.id == entry.id } }

    @discardableResult func setSaved(_ saved: Bool, entry: MediaEntry) async -> Bool {
        await load()
        guard loaded, !busy else { return false }
        busy = true
        defer { busy = false }
        var next = entries.filter { $0.id != entry.id }
        if saved { next.append(entry) }
        do {
            try await document.write(next)
            entries = next
            error = nil
            return true
        } catch {
            self.error = "Couldn’t save this profile’s library."
            return false
        }
    }
}

import Foundation
import Testing

@testable import Moku

@MainActor struct LibraryOrganizationTests {
    @Test func importsMergeAndOrganizationPersists() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = ProfileLibrary(directory: directory)
        await library.load()
        await library.loadOrganization()
        let title = MediaEntry(
            id: "one", title: "A title", media: .manga, sourceName: "Test", coverURL: nil)
        #expect(await library.setSaved(true, entry: title))
        let input = directory.appending(path: "import.json")
        try JSONEncoder().encode([title, title]).write(to: input)
        #expect(await library.importLibrary(from: input))
        #expect(library.entries.count == 1)
        let folder = LibraryFolder(name: "Favorites", entryIDs: [title.id])
        #expect(
            await library.saveOrganization(
                LibraryOrganization(folders: [folder], starred: [title.id])))
        let restored = ProfileLibrary(directory: directory)
        await restored.loadOrganization()
        #expect(restored.organization.folders == [folder])
        #expect(restored.organization.starred == [title.id])
        let model = LibraryViewModel()
        model.items = [
            LibraryItem(id: "one", title: "A title", media: .manga, bookmarked: true),
            LibraryItem(id: "two", title: "Other", media: .anime),
        ]
        model.tab = .starred
        #expect(model.visible(mode: .all).map(\.id) == ["one"])
        model.folder = folder
        model.clearFilters()
        #expect(model.tab == .starred)
        #expect(model.visible(mode: .anime).isEmpty)
        try Data("invalid".utf8).write(to: input)
        #expect(!(await library.importLibrary(from: input)))
        #expect(library.entries == [title])
    }
}

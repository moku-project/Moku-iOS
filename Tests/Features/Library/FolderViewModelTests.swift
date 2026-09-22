import Foundation
import Testing

@testable import Moku

@MainActor
struct FolderViewModelTests {
    @Test func folderCreationTrimsNamesAndPersistsAcrossReloads() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = LibraryStore(directory: directory)
        await library.loadOrganization()
        let model = FolderViewModel()
        model.name = " \n "
        #expect(await model.create(in: library) == nil)
        #expect(library.organization.folders.isEmpty)
        model.name = "  Favorites \n"
        let folder = try #require(await model.create(in: library))
        #expect(folder.name == "Favorites")
        #expect(!model.isSaving)
        let restored = LibraryStore(directory: directory)
        await restored.loadOrganization()
        #expect(restored.organization.folders == [folder])
    }
}

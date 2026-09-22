import Foundation
import Observation

@MainActor @Observable
final class FolderViewModel {
    var name = ""
    private(set) var isSaving = false
    var error: String?

    func create(in library: LibraryStore) async -> LibraryFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSaving else { return nil }
        isSaving = true
        error = nil
        defer { isSaving = false }
        let folder = LibraryFolder(name: trimmed)
        var next = library.organization
        next.folders.append(folder)
        guard await library.saveOrganization(next) else {
            error = library.error ?? "Couldn’t create the folder. Try again."
            return nil
        }
        return folder
    }
}

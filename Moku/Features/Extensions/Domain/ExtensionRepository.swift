import Foundation

protocol ExtensionRepository: Sendable {
    func repositories() async throws -> [ExtensionRepositoryInfo]
    func installed() async throws -> [SourceExtension]
    func catalog(
        query: String, repository: String?, language: String?, media: ContentMode, offset: Int
    ) async throws -> ExtensionPage
    func add(url: String, name: String) async throws
    func repositoryAction(_ action: RepositoryAction, id: String, name: String) async throws
    func extensionAction(_ action: ExtensionAction, package: String) async throws
    func preferences(package: String) async throws -> [SourcePreference]
    func savePreference(package: String, key: String, value: String) async throws
        -> [SourcePreference]
}

enum RepositoryAction: String, Sendable { case syncRepository, renameRepository, deleteRepository }
enum ExtensionAction: String, Sendable {
    case installExtension, updateExtension, uninstallExtension
}

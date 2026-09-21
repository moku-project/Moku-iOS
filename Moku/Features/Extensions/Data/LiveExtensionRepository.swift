import Foundation

struct LiveExtensionRepository: ExtensionRepository {
    private let api = BackendAPI.shared
    private static let fields =
        "id repositoryId packageName displayName version installedVersion lang contentType installed enabled needsUpdate isNsfw iconUrl"
    private static let preferenceFields =
        "key title summary type entries entryValues currentValue defaultValue"
    private struct Repositories: Decodable, Sendable { let repositories: [ExtensionRepositoryInfo] }
    private struct Installed: Decodable, Sendable { let installedExtensions: [SourceExtension] }
    private struct Catalog: Decodable, Sendable { let extensions: ExtensionPage }
    private struct Preferences: Decodable, Sendable { let sourcePreferences: [SourcePreference] }
    private struct Saved: Decodable, Sendable { let setSourcePreference: [SourcePreference] }
    private struct Mutation: Decodable, Sendable {}

    func repositories() async throws -> [ExtensionRepositoryInfo] {
        let result: Repositories = try await api.graphql(
            "{ repositories { id name indexUrl } }", requiresSourceRuntime: false)
        return result.repositories
    }
    func installed() async throws -> [SourceExtension] {
        let result: Installed = try await api.graphql(
            "{ installedExtensions { \(Self.fields) } }", requiresSourceRuntime: false)
        return result.installedExtensions
    }
    func catalog(
        query: String, repository: String?, language: String?, media: ContentMode, offset: Int
    ) async throws -> ExtensionPage {
        var args = ["query: \(BackendAPI.literal(query))", "limit: 40", "offset: \(offset)"]
        if let repository { args.append("repositoryId: \(BackendAPI.literal(repository))") }
        if let language { args.append("lang: \(BackendAPI.literal(language))") }
        if media != .all {
            args.append("contentType: \(media == .novels ? "NOVEL" : media.rawValue.uppercased())")
        }
        let result: Catalog = try await api.graphql(
            "{ extensions(\(args.joined(separator: ","))) { items { \(Self.fields) } total languages } }",
            requiresSourceRuntime: false
        )
        return result.extensions
    }
    func add(url: String, name: String) async throws {
        guard let parsed = URL(string: url), parsed.scheme == "https", parsed.host != nil else {
            throw EmbeddedSearchError.message("Enter a valid HTTPS repository index URL.")
        }
        let _: Mutation = try await api.graphql(
            "mutation { addRepository(indexUrl: \(BackendAPI.literal(url)), name: \(BackendAPI.literal(name))) { id } }",
            requiresSourceRuntime: false
        )
    }
    func repositoryAction(_ action: RepositoryAction, id: String, name: String = "") async throws {
        let nameArg = action == .renameRepository ? ", name: \(BackendAPI.literal(name))" : ""
        let fields = action == .deleteRepository ? "" : " { id }"
        let _: Mutation = try await api.graphql(
            "mutation { \(action.rawValue)(repositoryId: \(BackendAPI.literal(id))\(nameArg))\(fields) }",
            requiresSourceRuntime: false
        )
    }
    func extensionAction(_ action: ExtensionAction, package: String) async throws {
        let _: Mutation = try await api.graphql(
            "mutation { \(action.rawValue)(packageName: \(BackendAPI.literal(package))) { id } }")
    }
    func preferences(package: String) async throws -> [SourcePreference] {
        let result: Preferences = try await api.graphql(
            "{ sourcePreferences(extensionId: \(BackendAPI.literal(package))) { \(Self.preferenceFields) } }"
        )
        return result.sourcePreferences
    }
    func savePreference(package: String, key: String, value: String) async throws
        -> [SourcePreference]
    {
        let result: Saved = try await api.graphql(
            "mutation { setSourcePreference(extensionId: \(BackendAPI.literal(package)), key: \(BackendAPI.literal(key)), value: \(BackendAPI.literal(value))) { \(Self.preferenceFields) } }"
        )
        return result.setSourcePreference
    }
}

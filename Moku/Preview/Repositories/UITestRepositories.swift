import Foundation

#if DEBUG
    /// Deterministic UI-test data, available only with the explicit test launch argument.
    struct UITestSearchRepository: SearchRepository {
        func sources() async throws -> [SearchSource] {
            [
                SearchSource(
                    id: "fixture", name: "Test source", language: "en", media: .manga,
                    isPinned: true)
            ]
        }

        func search(_ request: SearchRequest) async throws -> [MediaEntry] {
            let entries = [
                MediaEntry(
                    id: "moon", title: "Moonflower", media: .manga, sourceName: "Test source",
                    coverURL: nil),
                MediaEntry(
                    id: "garden", title: "Moonlit Garden", media: .novels,
                    sourceName: "Test source", coverURL: nil),
            ]
            return entries.filter {
                (request.query.isEmpty || $0.title.localizedCaseInsensitiveContains(request.query))
                    && (request.options.media == .all || $0.media == request.options.media)
            }
        }
    }
#endif

#if DEBUG
    actor UITestExtensionRepository: ExtensionRepository {
        static let shared = UITestExtensionRepository()
        private var installedPackages: Set<String> = ["fixture"]
        private func item(_ package: String) -> SourceExtension {
            .init(
                id: package, repositoryId: "1", packageName: package,
                displayName: package == "fixture" ? "Test source" : "Another source",
                version: "1", installedVersion: installedPackages.contains(package) ? "1" : nil,
                lang: "en", contentType: "MANGA", installed: installedPackages.contains(package),
                enabled: true, needsUpdate: false, isNsfw: false)
        }
        func repositories() async throws -> [ExtensionRepositoryInfo] {
            [.init(id: "1", name: "Test repository", indexUrl: "https://example.com/index.json")]
        }
        func installed() async throws -> [SourceExtension] { installedPackages.sorted().map(item) }
        func catalog(
            query: String, repository: String?, language: String?, media: ContentMode,
            offset: Int
        ) async throws -> ExtensionPage {
            let items = [item("fixture"), item("another")].filter {
                query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)
            }
            return .init(items: items, total: items.count, languages: ["en"])
        }
        func add(url: String, name: String) async throws {}
        func repositoryAction(_ action: RepositoryAction, id: String, name: String) async throws {}
        func extensionAction(_ action: ExtensionAction, package: String) async throws {
            if action == .uninstallExtension {
                installedPackages.remove(package)
            } else {
                installedPackages.insert(package)
            }
        }
        func preferences(package: String) async throws -> [SourcePreference] { [] }
        func savePreference(package: String, key: String, value: String) async throws
            -> [SourcePreference]
        { [] }
    }
#endif

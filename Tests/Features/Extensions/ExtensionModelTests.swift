import Foundation
import Testing

@testable import Moku

@MainActor struct ExtensionModelTests {
    @Test func savedListsAppearWhileCatalogIsStillPending() async throws {
        let repository = ExtensionFixture()
        await repository.pauseNextCatalog()
        let model = ExtensionsViewModel(repository: repository)
        let loading = Task { await model.load() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.repositories.isEmpty || !model.installedLoaded, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.repositories.first?.title == "Saved repository")
        #expect(model.installedLoaded && model.installed.count == 1)
        #expect(model.isLoading && model.items.isEmpty)
        await repository.releaseCatalog()
        await loading.value
        #expect(!model.isLoading && model.items.count == 1)
    }

    @Test func supersededCatalogCannotOverwriteNewFilterResults() async throws {
        let repository = ExtensionFixture()
        await repository.pauseNextCatalog()
        let model = ExtensionsViewModel(repository: repository)
        let old = Task { await model.load() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await !repository.catalogIsPaused, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await repository.catalogIsPaused)
        model.query = "new"
        await model.load()
        #expect(model.items.isEmpty && !model.isLoading)
        await repository.releaseCatalog()
        await old.value
        #expect(model.items.isEmpty && !model.isLoading)
    }

    @Test func catalogFailureKeepsSavedRepositoriesAndInstalledSources() async {
        let repository = ExtensionFixture()
        await repository.configure(catalogFails: true)
        let model = ExtensionsViewModel(repository: repository)
        await model.load()
        #expect(model.repositories.count == 1)
        #expect(model.installed.count == 1 && model.installedLoaded)
        #expect(model.error?.contains("extension catalog") == true)
        #expect(!model.isLoading)
        await repository.configure()
        await model.load()
        #expect(model.error == nil && model.total == 1 && model.items.count == 1)
        await repository.configure(catalogFails: true)
        await model.load()
        #expect(model.items.count == 1 && model.repositories.count == 1)
    }

    @Test func installedFailureDoesNotHideCatalogOrPermitRepositoryRemoval() async {
        let repository = ExtensionFixture()
        await repository.configure(installedFails: true)
        let model = ExtensionsViewModel(repository: repository)
        await model.load()
        #expect(model.repositories.count == 1 && model.items.count == 1)
        #expect(!model.installedLoaded)
        #expect(model.error?.contains("installed sources") == true)
    }

    @Test func temporaryConnectionLossRetriesReadOnlyRequestOnce() async {
        let repository = ExtensionFixture()
        await repository.configure(loseFirstConnection: true)
        let model = ExtensionsViewModel(repository: repository)
        await model.load()
        #expect(model.error == nil && model.items.count == 1)
        #expect(await repository.catalogCalls == 2)
    }

    @Test func persistentConnectionLossStopsAfterOneRetry() async {
        let repository = ExtensionFixture()
        await repository.configure(catalogFails: true, loseFirstConnection: true)
        let model = ExtensionsViewModel(repository: repository)
        await model.load()
        #expect(model.error != nil && !model.isLoading)
        #expect(await repository.catalogCalls == 2)
        #expect(model.repositories.count == 1)
    }
}

private actor ExtensionFixture: ExtensionRepository {
    private var pauseCatalog = false
    private var catalogContinuation: CheckedContinuation<Void, Never>?
    var catalogIsPaused: Bool { catalogContinuation != nil }
    func pauseNextCatalog() { pauseCatalog = true }
    func releaseCatalog() {
        catalogContinuation?.resume()
        catalogContinuation = nil
    }
    var catalogFails = false
    var installedFails = false
    var loseFirstConnection = false
    private(set) var catalogCalls = 0
    let source = SourceExtension(
        id: "1", repositoryId: "1", packageName: "fixture",
        displayName: "Fixture", version: "1", installedVersion: "1", lang: "en",
        contentType: "MANGA", installed: true, enabled: true, needsUpdate: false, isNsfw: false)
    func configure(
        catalogFails: Bool = false, installedFails: Bool = false,
        loseFirstConnection: Bool = false
    ) {
        self.catalogFails = catalogFails
        self.installedFails = installedFails
        self.loseFirstConnection = loseFirstConnection
    }
    func repositories() async throws -> [ExtensionRepositoryInfo] {
        [.init(id: "1", name: "Saved repository", indexUrl: "https://example.com/index.pb")]
    }
    func installed() async throws -> [SourceExtension] {
        if installedFails { throw URLError(.badServerResponse) }
        return [source]
    }
    func catalog(
        query: String, repository: String?, language: String?, media: ContentMode,
        offset: Int
    ) async throws -> ExtensionPage {
        catalogCalls += 1
        if pauseCatalog {
            pauseCatalog = false
            await withCheckedContinuation { catalogContinuation = $0 }
        }
        if query == "new" { return .init(items: [], total: 0, languages: []) }
        if loseFirstConnection && (catalogCalls == 1 || catalogFails) {
            throw URLError(.networkConnectionLost)
        }
        if catalogFails { throw URLError(.badServerResponse) }
        return .init(items: [source], total: 1, languages: ["en"])
    }
    func add(url: String, name: String) async throws {}
    func repositoryAction(_ action: RepositoryAction, id: String, name: String) async throws {}
    func extensionAction(_ action: ExtensionAction, package: String) async throws {}
    func preferences(package: String) async throws -> [SourcePreference] { [] }
    func savePreference(package: String, key: String, value: String) async throws
        -> [SourcePreference]
    { [] }
}

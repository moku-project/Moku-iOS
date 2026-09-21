import Foundation
import Observation

@MainActor @Observable
final class ExtensionsViewModel {
    private let repository: any ExtensionRepository
    private(set) var repositories: [ExtensionRepositoryInfo] = []
    private(set) var installed: [SourceExtension] = []
    private(set) var items: [SourceExtension] = []
    private(set) var total = 0
    private(set) var languages: [String] = []
    private(set) var isLoading = true
    private(set) var isWorking = false
    private(set) var installedLoaded = false
    var error: String?
    var query = ""
    var repositoryID: String?
    var language: String?
    var media: ContentMode = .all
    @ObservationIgnored private var generation = 0

    init(repository: any ExtensionRepository) { self.repository = repository }

    var visibleInstalled: [SourceExtension] {
        installed.filter {
            (query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query))
                && (repositoryID == nil || $0.repositoryId == repositoryID)
                && (language == nil || $0.lang == language)
                && (media == .all || $0.media == media)
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func load(more: Bool = false) async {
        generation += 1
        let request = generation
        isLoading = true
        defer { if request == generation { isLoading = false } }
        let repository = repository
        let query = query
        let repositoryID = repositoryID
        let language = language
        let media = media
        let offset = more ? items.count : 0
        error = nil
        await withTaskGroup(of: SectionResult.self) { group in
            group.addTask {
                .repositories(await Self.result { try await repository.repositories() })
            }
            group.addTask { .installed(await Self.result { try await repository.installed() }) }
            group.addTask {
                .catalog(
                    await Self.result {
                        try await repository.catalog(
                            query: query, repository: repositoryID,
                            language: language, media: media, offset: offset)
                    })
            }
            var failures: [String] = []
            for await result in group {
                guard request == generation, !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                // Publish each independent SQLite read immediately. A slow catalog
                // must never hold the saved repository list behind a spinner.
                switch result {
                case .repositories(.success(let loaded)): repositories = loaded
                case .installed(.success(let loaded)):
                    installed = loaded
                    installedLoaded = true
                case .catalog(.success(let page)):
                    let existing = Set(items.map(\.id))
                    items =
                        more ? items + page.items.filter { !existing.contains($0.id) } : page.items
                    total = page.total
                    languages = page.languages
                case .repositories(.failure(let failure)):
                    failures.append(Self.message(failure, section: "repositories"))
                case .installed(.failure(let failure)):
                    installedLoaded = false
                    failures.append(Self.message(failure, section: "installed sources"))
                case .catalog(.failure(let failure)):
                    failures.append(Self.message(failure, section: "extension catalog"))
                }
                error = failures.isEmpty ? nil : failures.joined(separator: "\n")
            }
        }
    }

    private enum SectionResult: Sendable {
        case repositories(Result<[ExtensionRepositoryInfo], any Error>)
        case installed(Result<[SourceExtension], any Error>)
        case catalog(Result<ExtensionPage, any Error>)
    }

    private nonisolated static func result<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async -> Result<T, any Error> {
        do {
            do { return .success(try await operation()) } catch let error as URLError
                where [.networkConnectionLost, .cannotConnectToHost, .timedOut].contains(error.code)
            {
                // These are read-only catalog requests. Retry a stale loopback
                // connection once, without restarting the embedded JVM.
                try await Task.sleep(for: .milliseconds(250))
                return .success(try await operation())
            }
        } catch { return .failure(error) }
    }

    private nonisolated static func message(_ error: any Error, section: String) -> String {
        if let network = error as? URLError {
            if network.code == .cancelled {
                return "The request for \(section) was interrupted. Retry to reload."
            }
            return "Couldn’t connect to the backend to load \(section). Retry to reconnect."
        }
        if error is DecodingError {
            return
                "The backend returned an unreadable response for \(section). Retry or restart the app."
        }
        return "Couldn’t load \(section). "
            + ((error as? EmbeddedSearchError)?.errorDescription ?? "Try again.")
    }

    func perform(_ action: @Sendable (any ExtensionRepository) async throws -> Void) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await action(repository)
            await load()
            return true
        } catch {
            self.error =
                (error as? EmbeddedSearchError)?.errorDescription
                ?? "Couldn’t save this change. Try again."
            return false
        }
    }
}

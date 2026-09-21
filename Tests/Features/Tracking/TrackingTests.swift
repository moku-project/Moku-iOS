import Foundation
import Testing

@testable import Moku

@MainActor struct TrackingTests {
    private func remote() -> TrackingRemoteEntry {
        TrackingRemoteEntry(
            remoteId: "1", title: "Frieren", titleRomaji: "Sousou no Frieren",
            titleEnglish: "Frieren",
            status: "CURRENT", progress: 127, score: 8, coverUrl: nil)
    }
    @Test func matchingRequiresOneUnambiguousExactTitle() {
        let a = MediaEntry(
            id: "a", title: "FRIEREN", media: .manga, sourceName: "Source", coverURL: nil)
        let b = MediaEntry(
            id: "b", title: "Frieren", media: .manga, sourceName: "Source", coverURL: nil)
        #expect(TrackingViewModel.exactMatch(remote(), candidates: [a]) == a)
        #expect(TrackingViewModel.exactMatch(remote(), candidates: [a, b]) == nil)
        #expect(TrackingViewModel.exactMatch(remote(), candidates: []) == nil)
        #expect(LiveTrackingRepository.status("PLANNING") == 2)
        #expect(LiveTrackingRepository.status("COMPLETED") == 3)
        #expect(LiveTrackingRepository.status("PAUSED") == 4)
        #expect(LiveTrackingRepository.status("DROPPED") == 5)
    }
    @Test func dryRunDoesNotWriteAndImportResumesWithoutDuplicates() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = TrackingFake(entries: [remote()])
        let library = ProfileLibrary(directory: directory)
        let model = TrackingViewModel(repository: repo)
        await model.configure(directory: directory)
        await model.load()
        #expect(await model.fetchList(library: library))
        await model.runImport(library: library, dryRun: true)
        #expect(await repo.writes == 0)
        #expect(library.entries.isEmpty)
        await model.runImport(library: library, dryRun: false)
        #expect(await repo.writes == 1)
        #expect(library.entries.count == 1)
        let resumed = TrackingViewModel(repository: repo)
        await resumed.configure(directory: directory)
        await resumed.load()
        #expect(resumed.items.first?.state == .imported)
        await resumed.runImport(library: library, dryRun: false)
        #expect(await repo.writes == 1)
        #expect(await resumed.fetchList(library: library))
        #expect(resumed.items.first?.state == .existing)
    }
    @Test func failedImportsCanRetryAndChangedAccountsCannotResume() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = TrackingFake(entries: [remote()])
        let library = ProfileLibrary(directory: directory)
        let model = TrackingViewModel(repository: repo)
        await model.configure(directory: directory)
        await model.load()
        #expect(await model.fetchList(library: library))
        await repo.setFailure(true)
        await model.runImport(library: library, dryRun: false)
        #expect(model.items.first?.state == .failed)
        #expect(library.entries.isEmpty)
        #expect(model.failureReport.contains("Frieren"))
        await repo.setFailure(false)
        await repo.setUsername("another_account")
        await model.load()
        await model.runImport(library: library, dryRun: false)
        #expect(await repo.writes == 1)
        #expect(model.notice?.contains("account changed") == true)
        await repo.setUsername("reader")
        await model.load()
        await model.runImport(library: library, dryRun: false)
        #expect(model.items.first?.state == .imported)
        #expect(await repo.writes == 2)
    }
}

private actor TrackingFake: TrackingRepository {
    let entries: [TrackingRemoteEntry]
    var writes = 0
    var failure = false
    var username = "reader"
    init(entries: [TrackingRemoteEntry]) { self.entries = entries }
    func setFailure(_ value: Bool) { failure = value }
    func setUsername(_ value: String) { username = value }
    func services() async throws -> [TrackingService] {
        [
            TrackingService(
                key: "anilist", name: "AniList", configured: true, isLoggedIn: true,
                authUrl: nil, iconUrl: nil, username: username)
        ]
    }
    func login(key: String, token: String) async throws {}
    func logout(key: String) async throws {}
    func list(key: String, media: ContentMode, statuses: Set<String>) async throws
        -> [TrackingRemoteEntry]
    { entries }
    func importTitle(_ item: TrackingImportItem, key: String, media: ContentMode) async throws
        -> MediaEntry
    {
        writes += 1
        if failure { throw TrackingError.message("offline") }
        return MediaEntry(
            id: item.id, title: item.remote.title, media: media, sourceName: "AniList",
            coverURL: nil,
            externalID: "\(key):\(item.id)")
    }
}

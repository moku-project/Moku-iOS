import Testing

@testable import Moku

@MainActor struct DownloadsModelTests {
    @Test func retryIsScopedAndPreservesOtherStates() {
        let model = DownloadsViewModel(entries: [
            .init(id: "1", titleID: "a", title: "A", chapter: "1", status: .failed),
            .init(id: "2", titleID: "a", title: "A", chapter: "2", status: .failed),
            .init(id: "3", titleID: "b", title: "B", chapter: "3", status: .failed),
            .init(id: "4", titleID: "a", title: "A", chapter: "4", status: .completed),
        ])
        model.retry(entryID: "1")
        #expect(model.entries.map(\.status) == [.queued, .failed, .failed, .completed])
        model.retry(titleID: "a")
        #expect(model.entries.map(\.status) == [.queued, .queued, .failed, .completed])
        #expect(model.groups(history: false).map(\.id) == ["a", "b"])
        model.clear(history: true)
        #expect(model.entries.count == 3)
        #expect(model.count(history: true) == 0)
    }
}

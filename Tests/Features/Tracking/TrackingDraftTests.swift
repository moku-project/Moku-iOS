import Foundation
import Testing

@testable import Moku

@MainActor
struct TrackingDraftTests {
    @Test func queuedSnapshotsRestoreTheMostRecentDraft() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = TrackingViewModel()
        await model.configure(directory: directory)
        for index in 0..<25 {
            model.trackerKey = "tracker-\(index)"
            model.statuses = ["status-\(index)"]
            model.persist()
        }
        await model.flushDraft()
        let restored = TrackingViewModel()
        await restored.configure(directory: directory)
        #expect(restored.trackerKey == "tracker-24")
        #expect(restored.statuses == ["status-24"])
        #expect(model.notice == nil)
    }

    @Test func failedDraftWriteKeepsStateAndReportsTheFailure() async throws {
        let file = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("not a directory".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let model = TrackingViewModel()
        await model.configure(directory: file)
        model.trackerKey = "unsaved-tracker"
        model.persist()
        await model.flushDraft()
        #expect(model.trackerKey == "unsaved-tracker")
        #expect(model.notice?.contains("Couldn’t save import progress") == true)
        #expect(try Data(contentsOf: file) == Data("not a directory".utf8))
    }
}

import Foundation
import Testing

@testable import Moku

@MainActor struct ReadingHistoryTests {
    private actor Capture: ReadingHistoryRepository {
        var recorded: [ReadingSessionInput] = []
        var imported: ([ReadingSessionInput], [ReadingDayInput])?
        func sessions(limit: Int) async throws -> [HistorySession] { [] }
        func statistics(timeZone: String) async throws -> HomeStatistics { HomeStatistics() }
        func record(_ session: ReadingSessionInput) async throws { recorded.append(session) }
        func importHistory(source: String, sessions: [ReadingSessionInput], days: [ReadingDayInput])
            async throws
        {
            imported = (sessions, days)
        }
        func clear(mediaID: String?) async throws {}
        func reset() async throws {}
        func resumePoint(mediaID: String) async throws -> ResumePoint? { nil }
        /// The latest version of each session the recorder sent.
        func sessions() -> [ReadingSessionInput] {
            var latest: [String: ReadingSessionInput] = [:]
            var order: [String] = []
            for session in recorded {
                if latest[session.id] == nil { order.append(session.id) }
                latest[session.id] = session
            }
            return order.compactMap { latest[$0] }
        }
    }

    private func settle(_ capture: Capture, count: Int) async throws -> [ReadingSessionInput] {
        for _ in 0..<100 {
            let sessions = await capture.sessions()
            if sessions.count >= count, await capture.recorded.count > 0 { return sessions }
            try await Task.sleep(for: .milliseconds(10))
        }
        return await capture.sessions()
    }

    @Test func oneSessionSpansChaptersAndSkipsPausedTime() async throws {
        let capture = Capture()
        let history = ReadingHistory(repository: capture)
        let recorder = ActivityRecorder()
        func sample(_ chapter: String, _ seconds: Double, page: Int = 3, active: Bool = true) {
            recorder.sample(
                history: history, mediaID: "1", chapterID: chapter, position: page, active: active,
                valid: true,
                now: Date(timeIntervalSince1970: seconds))
        }
        sample("10", 0)
        sample("10", 60, active: false)
        sample("10", 600)
        sample("11", 660, page: 7)
        recorder.stop(history: history, now: Date(timeIntervalSince1970: 720))
        try await Task.sleep(for: .milliseconds(100))
        let sessions = try await settle(capture, count: 1)
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.startChapterID == "10" && session.endChapterID == "11")
        #expect(session.endPage == 7 && session.chapters == 2)
        #expect(session.durationMs == 180_000)
    }

    @Test func anHourIdleOrAnotherTitleStartsANewSession() async throws {
        let capture = Capture()
        let history = ReadingHistory(repository: capture)
        let recorder = ActivityRecorder()
        func sample(_ media: String, _ seconds: Double, active: Bool = true) {
            recorder.sample(
                history: history, mediaID: media, chapterID: "c", position: 1, active: active,
                valid: true,
                now: Date(timeIntervalSince1970: seconds))
        }
        sample("1", 0)
        sample("1", 60, active: false)
        sample("1", 60 + ActivityRecorder.idleLimit + 1)
        sample("1", 60 + ActivityRecorder.idleLimit + 61)
        sample("2", 60 + ActivityRecorder.idleLimit + 121)
        recorder.stop(
            history: history,
            now: Date(timeIntervalSince1970: 60 + ActivityRecorder.idleLimit + 181))
        try await Task.sleep(for: .milliseconds(100))
        let sessions = try await settle(capture, count: 3)
        #expect(sessions.map(\.mediaID) == ["1", "1", "2"])
        #expect(Set(sessions.map(\.id)).count == 3)
    }

    @Test func openingWithoutReadingRecordsNothing() async throws {
        let capture = Capture()
        let history = ReadingHistory(repository: capture)
        let recorder = ActivityRecorder()
        recorder.sample(
            history: history, mediaID: "1", chapterID: "c", position: 1, active: true, valid: true,
            now: Date(timeIntervalSince1970: 0))
        recorder.stop(history: history, now: Date(timeIntervalSince1970: 2))
        try await Task.sleep(for: .milliseconds(100))
        #expect(await capture.recorded.isEmpty)
    }

    @Test func legacyHistoryBecomesServerSessionsAndDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let (sessions, days) = LegacyHistoryImport.convert(
            [
                (UUID(), "12", "40", 9, day, 5, 2, nil, 300),
                (UUID(), "12", "41", 1, day.addingTimeInterval(600), 0, 0, nil, 7200),
                (UUID(), "local-file", "1", 1, day, 3, 1, nil, nil),
            ], calendar: calendar)
        #expect(sessions.count == 2)
        #expect(
            sessions[0].mediaID == "12" && sessions[0].endChapterID == "40"
                && sessions[0].endPage == 9)
        #expect(sessions[1].durationMs == 3_600_000)
        #expect(days.count == 1)
        #expect(days[0].seconds == 300 + 3600 + 180 && days[0].chapters == 2 + 1 + 1)
    }

    @Test func recentKeepsTheLatestSessionPerTitle() async {
        let history = HomePreviewData.makeStore()
        await history.refresh()
        #expect(history.recent.map(\.mediaID) == ["talent", "wild", "overgeared"])
        await history.clear(mediaID: "wild")
        #expect(history.recent.map(\.mediaID) == ["talent", "overgeared"])
        await history.reset()
        #expect(history.sessions.isEmpty)
    }
}

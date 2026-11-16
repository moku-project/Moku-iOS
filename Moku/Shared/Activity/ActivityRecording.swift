import SwiftUI

/// Builds one reading session per stretch on a title: it ends when the title changes or after an hour idle.
@MainActor final class ActivityRecorder {
    private struct Draft {
        let id = UUID().uuidString
        let mediaID: String
        let startChapterID: String
        let startPage: Int
        let startedAt: Date
        var endChapterID: String
        var endPage: Int
        var endedAt: Date
        var seconds: TimeInterval = 0
        var chapters: Set<String>
    }

    static let idleLimit: TimeInterval = 3600
    private var draft: Draft?
    private var previousTime: Date?
    private var wasActive = false
    private var lastSent: Date?

    func sample(
        history: ReadingHistory, mediaID: String, chapterID: String, position: Int,
        active: Bool, valid: Bool, now: Date = .now
    ) {
        accumulate(now: now)
        if let current = draft, current.mediaID != mediaID || now.timeIntervalSince(current.endedAt) > Self.idleLimit {
            send(history: history)
            draft = nil
        }
        let reading = active && valid
        let stopped = wasActive && !reading
        wasActive = reading
        previousTime = now
        guard valid else {
            if stopped { send(history: history) }
            return
        }
        if draft == nil {
            guard reading else { return }
            draft = Draft(
                mediaID: mediaID, startChapterID: chapterID, startPage: max(1, position), startedAt: now,
                endChapterID: chapterID, endPage: max(1, position), endedAt: now, chapters: [chapterID])
        }
        let newChapter = draft?.chapters.insert(chapterID).inserted ?? false
        draft?.endChapterID = chapterID
        draft?.endPage = max(1, position)
        if reading { draft?.endedAt = now }
        if newChapter || stopped || lastSent.map({ now.timeIntervalSince($0) >= 30 }) ?? true {
            send(history: history, now: now)
        }
    }

    func stop(history: ReadingHistory, now: Date = .now) {
        accumulate(now: now)
        wasActive = false
        previousTime = nil
        send(history: history, now: now)
    }

    private func accumulate(now: Date) {
        guard wasActive, let previousTime else { return }
        draft?.seconds += min(Self.idleLimit, max(0, now.timeIntervalSince(previousTime)))
        draft?.endedAt = now
    }

    private func send(history: ReadingHistory, now: Date = .now) {
        // Opening and closing without reading leaves no history.
        guard let draft, draft.seconds >= 5 || draft.chapters.count > 1 else { return }
        lastSent = now
        let input = ReadingSessionInput(
            id: draft.id, mediaID: draft.mediaID, startChapterID: draft.startChapterID,
            endChapterID: draft.endChapterID, startPage: draft.startPage, endPage: draft.endPage,
            startedAt: draft.startedAt, endedAt: max(draft.endedAt, draft.startedAt),
            durationMs: Int(min(Self.idleLimit, draft.seconds) * 1000), chapters: draft.chapters.count)
        Task { await history.record(input) }
    }
}

private struct ActivityRecording: ViewModifier {
    @Environment(ReadingHistory.self) private var history: ReadingHistory?
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = ActivityRecorder()
    let mediaID: String
    let chapterID: String
    let position: Int
    let active: Bool
    let valid: Bool

    private struct Sample: Equatable {
        let chapterID: String
        let position: Int
        let active: Bool
        let valid: Bool
    }
    private var sample: Sample {
        Sample(chapterID: chapterID, position: position, active: active && scenePhase == .active, valid: valid)
    }
    func body(content: Content) -> some View {
        content
            .onChange(of: sample, initial: true) { _, _ in record() }
            .task(id: sample) {
                guard sample.active && sample.valid else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { break }
                    record()
                }
            }
            .onDisappear { if let history { recorder.stop(history: history) } }
    }
    private func record() {
        guard let history else { return }
        recorder.sample(
            history: history, mediaID: mediaID, chapterID: chapterID, position: position,
            active: sample.active, valid: valid)
    }
}

extension View {
    func recordActivity(mediaID: String, chapterID: String, position: Int, active: Bool, valid: Bool) -> some View {
        modifier(ActivityRecording(mediaID: mediaID, chapterID: chapterID, position: position, active: active, valid: valid))
    }
}

import SwiftUI

/// A session is replaced as progress changes, and split when its chapter changes.
/// Only foreground reading / actual playback contributes elapsed time.
@MainActor final class ActivityRecorder {
    private var session: HomeSession?
    private var entry: HomeEntry?
    private var seconds: TimeInterval = 0
    private var previousTime: Date?
    private var wasActive = false

    func sample(
        home: HomeStore, entry: HomeEntry, chapterID: String, position: Int,
        completed: Bool, active: Bool, valid: Bool, now: Date = .now
    ) {
        if let previousTime, wasActive {
            seconds += max(0, now.timeIntervalSince(previousTime))
            session?.endedAt = now
        }
        previousTime = now
        wasActive = active && valid
        if session?.chapterID != chapterID || session?.entryID != entry.id {
            persist(home: home, now: now)
            session = nil
            seconds = 0
        }
        guard valid else {
            persist(home: home, now: now)
            return
        }
        self.entry = entry
        if session == nil {
            guard active else { return }
            session = HomeSession(
                entryID: entry.id, chapterID: chapterID, page: position,
                endedAt: now, minutes: 0, completedUnits: 0)
        }
        session?.page = position
        let units = max(session?.completedUnits ?? 0, completed ? 1 : 0)
        session?.completedUnits = units
        persist(home: home, now: now)
    }

    func stop(home: HomeStore, now: Date = .now) {
        if let previousTime, wasActive {
            seconds += max(0, now.timeIntervalSince(previousTime))
            session?.endedAt = now
        }
        wasActive = false
        previousTime = nil
        persist(home: home, now: now)
    }

    private func persist(home: HomeStore, now: Date) {
        guard var session, let entry else { return }
        session.minutes = Int(seconds / 60)
        // Paused sessions don't continually jump to the top of Recent.
        if wasActive { session.endedAt = now }
        self.session = session
        home.record(session, entry: entry)
    }
}

private struct ActivityRecording: ViewModifier {
    @Environment(HomeStore.self) private var home: HomeStore?
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = ActivityRecorder()
    let entry: HomeEntry
    let chapterID: String
    let position: Int
    let completed: Bool
    let active: Bool
    let valid: Bool

    private struct Sample: Equatable {
        let chapterID: String
        let position: Int
        let completed: Bool
        let active: Bool
        let valid: Bool
    }
    private var sample: Sample {
        Sample(
            chapterID: chapterID, position: position, completed: completed,
            active: active && scenePhase == .active, valid: valid)
    }
    func body(content: Content) -> some View {
        content
            .onChange(of: sample, initial: true) { _, _ in record() }
            .task(id: sample) {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) } catch { break }
                    record()
                }
            }
            .onDisappear { if let home { recorder.stop(home: home) } }
    }
    private func record() {
        guard let home else { return }
        recorder.sample(
            home: home, entry: entry, chapterID: chapterID, position: position,
            completed: completed, active: sample.active, valid: valid)
    }
}

extension View {
    func recordActivity(
        entry: HomeEntry, chapterID: String, position: Int,
        completed: Bool, active: Bool, valid: Bool
    ) -> some View {
        modifier(
            ActivityRecording(
                entry: entry, chapterID: chapterID, position: position,
                completed: completed, active: active, valid: valid))
    }
}

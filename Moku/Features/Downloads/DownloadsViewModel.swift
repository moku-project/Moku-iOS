import Foundation
import Observation

/// Presentation state. The chapter transfer service will supply entries and execute actions.
/// Production starts empty; sample transfers are restricted to the UI-test launch argument.
@MainActor @Observable
final class DownloadsViewModel {
    var entries: [DownloadEntry]
    var isPaused = false
    var autoRetry = false

    init(entries: [DownloadEntry] = []) { self.entries = entries }

    func count(history: Bool) -> Int {
        entries.filter { ($0.status == .completed) == history }.count
    }

    private func matches(_ entry: DownloadEntry, section: DownloadsSection, history: Bool) -> Bool {
        let inView =
            history
            ? entry.status == .completed || entry.status == .failed
            : entry.status != .completed
        return inView && section.includes(entry)
    }

    func count(section: DownloadsSection, history: Bool) -> Int {
        entries.filter { matches($0, section: section, history: history) }.count
    }

    func groups(section: DownloadsSection, history: Bool) -> [DownloadGroup] {
        grouped(entries.filter { matches($0, section: section, history: history) })
    }

    func clear(section: DownloadsSection, history: Bool) {
        let ids = Set(entries.filter { matches($0, section: section, history: history) }.map(\.id))
        entries.removeAll { ids.contains($0.id) }
    }

    func groups(history: Bool) -> [DownloadGroup] {
        grouped(entries.filter { ($0.status == .completed) == history })
    }

    private func grouped(_ visible: [DownloadEntry]) -> [DownloadGroup] {
        var order: [String] = []
        var grouped: [String: [DownloadEntry]] = [:]
        for entry in visible {
            if grouped[entry.titleID] == nil { order.append(entry.titleID) }
            grouped[entry.titleID, default: []].append(entry)
        }
        return order.map { DownloadGroup(id: $0, entries: grouped[$0] ?? []) }
    }

    func retry(entryID: String? = nil, titleID: String? = nil) {
        for index in entries.indices where entries[index].status == .failed {
            guard entryID == nil || entries[index].id == entryID,
                titleID == nil || entries[index].titleID == titleID
            else { continue }
            entries[index].status = .queued
            entries[index].progress = 0
        }
    }

    func clear(history: Bool) {
        entries.removeAll { ($0.status == .completed) == history }
    }

    static func makeDefault() -> DownloadsViewModel {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-downloads") {
                return DownloadsViewModel(entries: [
                    .init(
                        id: "1", titleID: "talent", title: "I’m Not That Kind of Talent",
                        chapter: "Chapter 14", status: .downloading, progress: 0.65),
                    .init(
                        id: "2", titleID: "talent", title: "I’m Not That Kind of Talent",
                        chapter: "Chapter 15", status: .queued),
                    .init(
                        id: "3", titleID: "monster", title: "Monster But Wild",
                        chapter: "Chapter 8", status: .failed),
                    .init(
                        id: "4", titleID: "monster", title: "Monster But Wild",
                        chapter: "Chapter 9", status: .failed),
                    .init(
                        id: "5", titleID: "overgeared", title: "Overgeared", chapter: "Chapter 24",
                        status: .queued),
                    .init(
                        id: "6", titleID: "history", title: "Omniscient Reader",
                        chapter: "Chapter 12", status: .completed, bytes: 24_000_000,
                        completedAt: Date()),
                ])
            }
        #endif
        return DownloadsViewModel()
    }
}

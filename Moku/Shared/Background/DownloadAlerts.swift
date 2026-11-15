import Foundation
import UIKit
import UserNotifications

/// Announces when a title's queued downloads finish: a toast in the app, a local notification in the background.
@MainActor final class DownloadAlerts {
    static let shared = DownloadAlerts()
    static let enabledKey = "downloads.notifications"

    struct Item: Sendable {
        let titleID: String
        let chapterID: String
        var title: String?
        let status: DownloadStatus
    }

    private var pending: [String: Set<String>]?
    private var lastObserved = Date.distantPast
    private var titles: [String: String] = [:]

    static var enabled: Bool {
        AppDataStore.shared.preferences.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Feeds one queue snapshot; titles whose pending chapters all left the queue are announced.
    func observe(_ items: [Item]) {
        for item in items { if let title = item.title { titles[item.titleID] = title } }
        var next: [String: Set<String>] = [:]
        for item in items where item.status == .queued || item.status == .downloading {
            next[item.titleID, default: []].insert(item.chapterID)
        }
        // A stale baseline would announce downloads that finished long ago.
        let previous = Date().timeIntervalSince(lastObserved) < 30 ? pending : nil
        pending = next
        lastObserved = Date()
        guard let previous, Self.enabled else { return }
        let status = Dictionary(items.map { ($0.chapterID, $0.status) }, uniquingKeysWith: { first, _ in first })
        for (titleID, chapters) in previous where next[titleID] == nil {
            let done = chapters.filter { status[$0] == .completed }.count
            let failed = chapters.filter { status[$0] == .failed }.count
            guard done + failed > 0 else { continue }
            Task { await announce(titleID: titleID, done: done, failed: failed) }
        }
    }

    private func announce(titleID: String, done: Int, failed: Int) async {
        let title = await name(titleID)
        let unit = done == 1 ? "chapter" : "chapters"
        let detail = failed > 0 ? "\(done) \(unit) downloaded, \(failed) failed" : "\(done) \(unit) downloaded"
        if UIApplication.shared.applicationState == .active {
            Toaster.shared.show(failed > 0 ? "Downloads finished with errors" : "Downloaded \(title)",
                                detail: failed > 0 ? "\(title): \(detail)" : detail,
                                kind: failed > 0 ? .error : .download)
            return
        }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = detail
        content.sound = .default
        content.threadIdentifier = "downloads"
        try? await center.add(UNNotificationRequest(identifier: "download-\(titleID)", content: content, trigger: nil))
    }

    private func name(_ titleID: String) async -> String {
        if let title = titles[titleID] { return title }
        struct Response: Decodable, Sendable { struct Media: Decodable, Sendable { let title: String }; let media: Media? }
        let response: Response? = try? await BackendAPI.shared.graphql(
            "{ media(id: \(BackendAPI.literal(titleID))) { title } }", requiresSourceRuntime: false)
        let title = response?.media?.title ?? "Downloads"
        titles[titleID] = title
        return title
    }
}

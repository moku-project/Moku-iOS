import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

/// iOS counterpart of desktop's always-on server: downloads keep going for a
/// while after leaving the app, and a processing task (idle, on network)
/// updates the library, notifies about new chapters and drains the queue.
@MainActor enum BackgroundWork {
    static let maintenanceID = "com.moku.app.maintenance"
    private static var foregroundTask: UIBackgroundTaskIdentifier = .invalid

    /// Must run before launch finishes.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: maintenanceID, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return task.setTaskCompleted(success: false) }
            MainActor.assumeIsolated { run(task) }
        }
    }

    /// Called when the app goes to the background.
    static func didEnterBackground(defaults: UserDefaults) {
        let updates = defaults.bool(forKey: "automation.backgroundUpdates")
        Task {
            let pending = (try? await pendingDownloads()) ?? 0
            if pending > 0 { keepDownloading() }
            if updates || pending > 0 { schedule() }
        }
    }

    private static func schedule() {
        let request = BGProcessingTaskRequest(identifier: maintenanceID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Uses the few minutes iOS grants after backgrounding to finish the queue.
    private static func keepDownloading() {
        guard foregroundTask == .invalid else { return }
        foregroundTask = UIApplication.shared.beginBackgroundTask(withName: "Downloads") { end() }
        Task {
            while foregroundTask != .invalid {
                try? await Task.sleep(for: .seconds(5))
                if UIApplication.shared.applicationState == .active { break }
                if ((try? await pendingDownloads()) ?? 0) == 0 { break }
            }
            end()
        }
    }

    private static func end() {
        guard foregroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(foregroundTask)
        foregroundTask = .invalid
    }

    private static func run(_ task: BGProcessingTask) {
        let work = Task { @MainActor in
            defer { schedule() }
            // A background launch may not have shown any UI yet.
            await AppDataStore.shared.load()
            let defaults = AppDataStore.shared.preferences
            do {
                if defaults.bool(forKey: "automation.backgroundUpdates") {
                    let repository = LiveRecentRepository()
                    try await repository.startLibraryUpdate()
                    try await Task.sleep(for: .seconds(1))
                    var status = try await repository.libraryUpdateStatus()
                    while status.running {
                        try await Task.sleep(for: .seconds(3))
                        status = try await repository.libraryUpdateStatus()
                    }
                    if status.newChapterCount > 0 { await notify(count: status.newChapterCount) }
                }
                if try await pendingDownloads() > 0 {
                    let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql("mutation { startDownloader }")
                    while try await pendingDownloads() > 0 { try await Task.sleep(for: .seconds(5)) }
                }
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = { work.cancel() }
    }

    private static func pendingDownloads() async throws -> Int {
        struct Response: Decodable, Sendable {
            struct Item: Decodable, Sendable { let status: String }
            let downloadQueue: [Item]
        }
        let response: Response = try await BackendAPI.shared.graphql(
            "{ downloadQueue { status } }", refresh: true, requiresSourceRuntime: false)
        return response.downloadQueue.filter { $0.status == "QUEUED" || $0.status == "DOWNLOADING" }.count
    }

    private static func notify(count: Int) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "New chapters"
        content.body = "\(count) new chapter\(count == 1 ? "" : "s") or episode\(count == 1 ? "" : "s") in your library. Open Recent → Updates."
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "library-updates", content: content, trigger: nil))
    }

    /// Asked when the user turns background updates on.
    static func requestNotificationPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}

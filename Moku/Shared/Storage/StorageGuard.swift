import UIKit

/// Before queueing downloads, asks first when their estimated size exceeds 95% of free space.
@MainActor enum StorageGuard {
    /// Desktop's estimate: 1.5 MB a page and 20 pages a chapter; about 300 MB an episode.
    static func estimate(count: Int, media: ContentMode) -> Int64 {
        Int64(count) * (media == .anime ? 300_000_000 : media == .novels ? 200_000 : 30_000_000)
    }

    static func freeBytes() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// True when there is room or the user chose "Download anyway".
    static func allow(count: Int, media: ContentMode) async -> Bool {
        guard let free = freeBytes(),
            estimate(count: count, media: media) > Int64(Double(free) * 0.95)
        else { return true }
        guard let presenter = topController() else { return true }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Low disk space",
                message:
                    "These downloads are estimated to use more than 95% of the space left on this device (\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free). Download anyway?",
                preferredStyle: .alert)
            alert.addAction(
                UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    continuation.resume(returning: false)
                })
            alert.addAction(
                UIAlertAction(title: "Download anyway", style: .default) { _ in
                    continuation.resume(returning: true)
                })
            presenter.present(alert, animated: true)
        }
    }

    private static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

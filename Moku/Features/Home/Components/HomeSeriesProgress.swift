import SwiftUI

/// Thin read/total bar for a continue-reading title, drawn only when Home has its chapter list.
struct HomeSeriesProgress: View {
    let entry: HomeEntry

    static func counts(_ entry: HomeEntry) -> (read: Int, total: Int)? {
        let total = entry.chapters.count
        guard total > 0 else { return nil }
        let read = entry.chapters.filter(\.isRead).count
        return (read, total)
    }

    var body: some View {
        if let counts = Self.counts(entry) {
            ProgressView(value: Double(counts.read), total: Double(counts.total))
                .progressViewStyle(.linear)
                .tint(NavigationStyle.accent)
                .accessibilityLabel("Series progress")
                .accessibilityValue(
                    "\(counts.read) of \(counts.total) \(entry.media == "Anime" ? "watched" : "read")"
                )
        }
    }
}

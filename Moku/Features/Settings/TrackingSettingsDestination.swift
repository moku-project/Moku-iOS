import SwiftUI

struct TrackingSettingsDestination: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TrackingView(settingsPage: true)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                BackHeader(title: "Tracking", backLabel: "Back to Settings") { dismiss() }
            }
    }
}

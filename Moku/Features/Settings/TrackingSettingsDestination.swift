import SwiftUI

struct TrackingSettingsDestination: View {
    var body: some View {
        TrackingView(settingsPage: true)
            .navigationTitle("Tracker Accounts")
            .navigationBarTitleDisplayMode(.inline)
    }
}

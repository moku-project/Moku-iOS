import SwiftUI

struct MoreDestinationView: View {
    let destination: MoreDestination
    @Binding var mode: ContentMode
    let searchSource: (SourceExtension) -> Void
    var body: some View {
        switch destination {
        case .recent: RecentView(mode: $mode)
        case .extensions:
            ExtensionsView(search: searchSource)
        case .tracking: TrackingView()
        case .about: AboutView()
        }

    }
}

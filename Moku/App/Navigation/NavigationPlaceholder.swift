import SwiftUI

struct NavigationPlaceholder: View {
    let title: String
    let symbol: String

    var body: some View {
        ScrollView {
            ContentUnavailableView {
                Label(title, phosphor: symbol)
            } description: {
                Text("This screen is ready for design.")
            }
        }
        .tracksNavigationScroll()
        .navigationTitle(title)
    }
}

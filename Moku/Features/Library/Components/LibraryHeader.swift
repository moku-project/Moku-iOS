import SwiftUI

struct LibraryHeader: View {
    @Binding var mode: ContentMode
    let dismissTools: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Library", showsDivider: false)
            ModeTabs(mode: $mode, prefix: "library", onSelect: dismissTools)
        }
    }
}

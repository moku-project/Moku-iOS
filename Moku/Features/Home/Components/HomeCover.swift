import SwiftUI

struct HomeCover: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode?
    var body: some View {
        CoverImage(url: url, contentMode: contentMode)
    }
}

import SwiftUI

struct HomeCover: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode? = .fit
    var alignment: Alignment = .center
    var body: some View {
        CoverImage(url: url, contentMode: contentMode, alignment: alignment)
    }
}

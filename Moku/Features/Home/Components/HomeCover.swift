import SwiftUI

struct HomeCover: View {
    let url: URL?
    var body: some View {
        CoverImage(url: url)
    }
}

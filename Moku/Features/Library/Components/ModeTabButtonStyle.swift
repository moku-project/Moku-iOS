import SwiftUI

/// Selection controls brightness; pressing alone leaves the label unchanged.
struct ModeTabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

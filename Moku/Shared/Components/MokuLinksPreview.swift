#if DEBUG
    import SwiftUI

    /// Open this file in Canvas with the Moku scheme selected.
    #Preview("Moku links modal") {
        @Previewable @State var isPresented = true

        ZStack {
            NavigationStyle.background.ignoresSafeArea()
            Button("Show Moku links") { isPresented = true }
                .tint(NavigationStyle.accent)
                .allowsHitTesting(!isPresented)
                .accessibilityHidden(isPresented)
            if isPresented {
                MokuLinksModal { isPresented = false }
            }
        }
        .preferredColorScheme(.dark)
    }
#endif

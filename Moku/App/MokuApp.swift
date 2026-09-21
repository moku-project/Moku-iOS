import SwiftUI
import UIKit

#if DEBUG
    import OSLog
#endif

@main
struct MokuApp: App {
    @Environment(\.scenePhase) private var scenePhase
    init() {
        // Stop at content boundaries so rebound motion cannot resize navigation.
        UIScrollView.appearance().bounces = false
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-testing-reader") {
                        ReaderPreview.view()
                    } else if ProcessInfo.processInfo.arguments.contains("--ui-testing-player") {
                        PlayerPreviewHost()
                    } else {
                        ProfileHostView()
                    }
                #else
                    ProfileHostView()
                #endif
            }
            #if DEBUG
                .onChange(of: scenePhase, initial: true) { _, phase in
                    UIResponsivenessMonitor.shared.setActive(phase == .active)
                }
            #endif
        }
    }
}

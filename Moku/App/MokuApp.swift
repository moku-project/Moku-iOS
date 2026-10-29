import SwiftUI
import UIKit

#if DEBUG
    import OSLog
#endif

@main
struct MokuApp: App {
    @Environment(\.scenePhase) private var scenePhase
    init() { BackgroundWork.register() }
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-testing-reader") {
                        ReaderPreview.view()
                    } else if ProcessInfo.processInfo.arguments.contains("--ui-testing-player") {
                        PlayerPreviewHost()
                    } else {
                        AppHostView()
                    }
                #else
                    AppHostView()
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

import Foundation

enum PreviewMode {
    static var isEnabled: Bool {
        #if DEBUG
            ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        #else
            false
        #endif
    }
}

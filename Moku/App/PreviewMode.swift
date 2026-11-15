import Foundation

enum PreviewMode {
    static var isEnabled: Bool {
        #if DEBUG
            ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        #else
            false
        #endif
    }

    /// True while the app only hosts unit tests. Tsunagu's core is one per
    /// process, and those tests start their own, so the host must not.
    static var isUnitTestHost: Bool {
        #if DEBUG
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
            false
        #endif
    }
}

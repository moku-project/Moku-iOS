import Foundation

enum PreviewMode {
    static var isEnabled: Bool {
        #if DEBUG
            ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        #else
            false
        #endif
    }

    /// True while only hosting unit tests, which start their own one-per-process core, so the host must not.
    static var isUnitTestHost: Bool {
        #if DEBUG
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
            false
        #endif
    }
}

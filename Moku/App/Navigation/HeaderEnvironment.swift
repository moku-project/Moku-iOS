import SwiftUI

extension EnvironmentValues {
    @Entry var openMokuLinks: @MainActor () -> Void = {}
    @Entry var openSettings: @MainActor () -> Void = {}
    @Entry var openContentTypes: @MainActor () -> Void = {}
}

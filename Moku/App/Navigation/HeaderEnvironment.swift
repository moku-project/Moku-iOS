import SwiftUI

extension EnvironmentValues {
    @Entry var openSettings: @MainActor () -> Void = {}
    @Entry var openProfile: @MainActor () -> Void = {}
}

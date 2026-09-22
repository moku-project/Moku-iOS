import SwiftUI

extension EnvironmentValues {
    @Entry var openSettings: @MainActor () -> Void = {}
}

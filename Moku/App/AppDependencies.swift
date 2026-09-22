import Foundation

enum AppDependencies {
    @MainActor static var homeStore: HomeStore {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-home-empty") {
                return HomeStore(fileURL: nil)
            }
            if PreviewMode.isEnabled
                || ProcessInfo.processInfo.arguments.contains("--ui-testing-home-populated")
            {
                return HomePreviewData.makeStore()
            }
        #endif
        return HomeStore()
    }

    static var extensionRepository: any ExtensionRepository {
        #if DEBUG
            if PreviewMode.isEnabled
                || ProcessInfo.processInfo.arguments.contains("--ui-testing-extensions")
            {
                return UITestExtensionRepository.shared
            }
        #endif
        return LiveExtensionRepository()
    }

    static var searchRepository: any SearchRepository {
        #if DEBUG
            if PreviewMode.isEnabled
                || ProcessInfo.processInfo.arguments.contains("--ui-testing-search")
            {
                return UITestSearchRepository()
            }
        #endif
        return LiveMediaRepository.shared
    }
}

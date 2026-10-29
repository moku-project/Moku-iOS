import Foundation

enum AppDependencies {
    @MainActor static var homeStore: HomeStore {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-home-empty") {
                return HomeStore(fileURL: nil)
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-home-one") {
                return HomePreviewData.makeStore(titleCount: 1)
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-home-two") {
                return HomePreviewData.makeStore(titleCount: 2)
            }
            if PreviewMode.isEnabled
                || ProcessInfo.processInfo.arguments.contains("--ui-testing-home-populated")
            {
                return HomePreviewData.makeStore()
            }
        #endif
        return HomeStore()
    }

    static var detailsRepository: any DetailsRepository {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-testing-home-") }) {
                return HomePreviewDetailsRepository()
            }
        #endif
        return LiveMediaRepository.shared
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

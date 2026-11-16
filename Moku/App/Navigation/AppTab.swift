import Observation

/// The app's tabs, in Android's order.
enum AppTab: String, CaseIterable, Identifiable {
    case home, browse, library, downloads, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .browse: "Search"
        case .downloads: "Downloads"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        case .browse: "magnifyingglass"
        case .downloads: "arrow.down.circle"
        case .settings: "gearshape"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .browse: "magnifyingglass"
        default: systemImage + ".fill"
        }
    }

    /// Tabs a user can choose to open the app on.
    static let startChoices: [AppTab] = [.home, .library, .browse, .downloads]
}

/// Places reached from the Settings tab, beside the settings categories.
enum MoreDestination: String, CaseIterable, Identifiable, Hashable {
    case extensions = "Extensions"
    case tracking = "Tracking"
    case recent = "History"
    case about = "About"
    var id: Self { self }
}

/// Per-page activity, so pages don't observe the global selected tab; identity survives navigation once mounted.
@MainActor @Observable final class TabActivity {
    fileprivate(set) var isActive = false
    fileprivate(set) var hasVisited = false
}

@MainActor final class TabActivityStore {
    private let pages = Dictionary(
        uniqueKeysWithValues: AppTab.allCases.map { ($0, TabActivity()) })

    init() { update(selection: .library, covered: false) }

    subscript(tab: AppTab) -> TabActivity { pages[tab]! }

    func update(selection: AppTab, covered: Bool) {
        for (tab, page) in pages {
            let active = tab == selection && !covered
            if page.isActive != active { page.isActive = active }
            if tab == selection && !page.hasVisited { page.hasVisited = true }
        }
    }
}

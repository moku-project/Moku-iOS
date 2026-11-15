import Observation

/// The app's tabs. Search is last: on iOS it takes the system search slot.
enum AppTab: String, CaseIterable, Identifiable {
    case home, library, downloads, settings, browse

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
    var systemImage: String {
        switch self {
        case .extensions: "puzzlepiece.extension"
        case .tracking: "chart.line.uptrend.xyaxis"
        case .recent: "clock.arrow.circlepath"
        case .about: "info.circle"
        }
    }
}

/// A page observes its own activity instead of the global selected-tab value.
/// Once mounted, its identity survives every subsequent navigation change.
@MainActor @Observable final class TabActivity {
    fileprivate(set) var isActive = false
    fileprivate(set) var hasVisited = false
}

@MainActor final class TabActivityStore {
    private let pages = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, TabActivity()) })

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

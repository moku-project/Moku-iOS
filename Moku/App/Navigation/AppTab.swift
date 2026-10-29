import Observation

enum AppTab: String, CaseIterable, Identifiable {
    case home, library, browse, downloads, more

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .browse: "Search"
        case .downloads: "Downloads"
        case .more: "More"
        }
    }

    var symbol: String {
        switch self {
        case .home: "House"
        case .library: "Books"
        case .browse: "MagnifyingGlass"
        case .downloads: "DownloadSimple"
        case .more: "DotsThreeCircle"
        }
    }
}

enum MoreDestination: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case tracking = "Tracking"
    case extensions = "Extensions"
    case about = "About"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .tracking: "TrendUp"
        case .recent: "ClockCounterClockwise"
        case .extensions: "PuzzlePiece"
        case .about: "Info"
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

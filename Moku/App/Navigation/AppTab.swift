import SwiftUI

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

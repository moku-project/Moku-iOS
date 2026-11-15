import Foundation

enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, compactGrid, covers, list, compactList
    var id: Self { self }
    var title: String {
        switch self {
        case .grid: "Grid"
        case .compactGrid: "Compact grid"
        case .covers: "Covers"
        case .list: "List"
        case .compactList: "Compact list"
        }
    }
    var symbol: String {
        switch self {
        case .grid: "SquaresFour"
        case .compactGrid: "GridNine"
        case .covers: "ImageSquare"
        case .list: "ListBullets"
        case .compactList: "Rows"
        }
    }
    var isList: Bool { self == .list || self == .compactList }
}

extension LibraryLayout {
    var systemImage: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .compactGrid: "square.grid.3x3"
        case .covers: "photo"
        case .list: "list.bullet"
        case .compactList: "list.dash"
        }
    }
}

extension LibraryTab {
    var systemImage: String {
        switch self {
        case .saved: "books.vertical"
        case .downloaded: "arrow.down.circle"
        case .starred: "star"
        case .reading: "book"
        case .completed: "checkmark.circle"
        }
    }
}

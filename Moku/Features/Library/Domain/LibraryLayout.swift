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

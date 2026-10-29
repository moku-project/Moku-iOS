import Foundation

enum SettingsCategory: String, CaseIterable, Hashable {
    case general = "General"
    case appearance = "Appearance"
    case reader = "Reader"
    case player = "Player"
    case library = "Library"
    case automation = "Automation"
    case tracking = "Tracking"
    case sync = "Sync"
    case performance = "Performance"
    case keybinds = "Keybinds"
    case storage = "Storage"
    case folders = "Folders"
    case content = "Content"
    case server = "Server"
    case auth = "Auth"
    case about = "About"
    case devTools = "Dev tools"

    /// Dev tools ship only in debug builds.
    static var visible: [SettingsCategory] {
        #if DEBUG
            allCases
        #else
            allCases.filter { $0 != .devTools }
        #endif
    }

    var symbol: String {
        switch self {
        case .general: "Gear"
        case .appearance: "PaintBrush"
        case .reader: "Book"
        case .player: "FilmSlate"
        case .library: "Image"
        case .automation: "Robot"
        case .tracking: "Broadcast"
        case .sync: "ArrowsClockwise"
        case .performance: "Sliders"
        case .keybinds: "Keyboard"
        case .storage: "HardDrives"
        case .folders: "FolderSimple"
        case .content: "ShieldCheck"
        case .server: "Database"
        case .auth: "LockKey"
        case .about: "Info"
        case .devTools: "Wrench"
        }
    }

}

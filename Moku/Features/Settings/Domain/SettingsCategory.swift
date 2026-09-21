import Foundation

enum SettingsCategory: String, CaseIterable, Hashable {
    case general = "General"
    case appearance = "Appearance"
    case reader = "Reader"
    case player = "Player"
    case library = "Library"
    case automation = "Automation"
    case tracking = "Tracking"
    case performance = "Performance"
    case keybinds = "Keybinds"
    case storage = "Storage"
    case folders = "Folders"
    case content = "Content"
    case server = "Server"
    case auth = "Auth"
    case about = "About"
    case devTools = "Dev Tools"

    var symbol: String {
        switch self {
        case .general: "Gear"
        case .appearance: "PaintBrush"
        case .reader: "Book"
        case .player: "FilmSlate"
        case .library: "Image"
        case .automation: "Robot"
        case .tracking: "Broadcast"
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

    var availability: String {
        switch self {
        case .reader: ""
        case .player:
            "Playback and subtitle preferences will be available when the iOS player is ready."
        case .automation: "Automatic downloads and cleanup aren’t available on iOS yet."
        case .tracking: "Tracking account connections and sync aren’t available on iOS yet."
        case .performance:
            "Desktop rendering and GPU controls don’t apply to iOS. This section is reserved for mobile performance settings."
        case .keybinds: "Keyboard shortcut customization isn’t available on iOS yet."
        case .folders: "Folder management isn’t available on iOS yet."
        case .content: "Content filters and source overrides aren’t available on iOS yet."
        case .server:
            "Moku runs Tsunagu on this device. External server configuration isn’t available on iOS yet."
        case .auth:
            "Profiles are stored on this device. Tsunagu server sign-in isn’t available on iOS."
        case .devTools: "Developer tools aren’t available on iOS yet."
        default: ""
        }
    }
}

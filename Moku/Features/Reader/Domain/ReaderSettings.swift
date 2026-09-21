import Foundation

struct MangaReadingSettings: Codable, Equatable, Sendable {
    var pageStyle = "longstrip"
    var transition = "none"
    var fitMode = "width"
    var readingDirection = "ltr"
    var readerZoom = 1.0
    var pageGap = true
    var optimizeContrast = false
    var offsetDoubleSpreads = false
    var barPosition = "top"
}

struct ReaderBehaviour: Codable, Equatable, Sendable {
    var autoMarkRead = true
    var autoNextChapter = true
    var markReadOnNext = true
    var autoBookmark = true
    var preloadPages = 3
    var pinchZoom = false
    var autoScroll = false
    var autoScrollSpeed = 5.0
    var tapToToggleBar = false
    var containerized = false
}

struct MangaReaderPreset: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var settings: MangaReadingSettings
}

struct ReaderPosition: Codable, Equatable, Sendable {
    var chapterID: String
    var page: Int
}

struct ReaderPreferenceDocument: Codable, Sendable {
    var global = MangaReadingSettings()
    var behaviour = ReaderBehaviour()
    var overrides: [String: MangaReadingSettings] = [:]
    var presets: [MangaReaderPreset] = []
    var positions: [String: ReaderPosition] = [:]
    var bookmarks: [String: ReaderPosition] = [:]
}

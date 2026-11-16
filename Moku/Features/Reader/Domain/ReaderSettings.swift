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
    /// Paged layouts: the outer 30 % on each side turns pages (mirrored for RTL), the middle 40 % toggles controls.
    var tapToTurn = true
}

/// Newer keys decode with defaults, so an older document never fails and resets every setting.
extension ReaderBehaviour {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReaderBehaviour()
        autoMarkRead = try c.decodeIfPresent(Bool.self, forKey: .autoMarkRead) ?? d.autoMarkRead
        autoNextChapter =
            try c.decodeIfPresent(Bool.self, forKey: .autoNextChapter) ?? d.autoNextChapter
        markReadOnNext =
            try c.decodeIfPresent(Bool.self, forKey: .markReadOnNext) ?? d.markReadOnNext
        autoBookmark = try c.decodeIfPresent(Bool.self, forKey: .autoBookmark) ?? d.autoBookmark
        preloadPages = try c.decodeIfPresent(Int.self, forKey: .preloadPages) ?? d.preloadPages
        pinchZoom = try c.decodeIfPresent(Bool.self, forKey: .pinchZoom) ?? d.pinchZoom
        autoScroll = try c.decodeIfPresent(Bool.self, forKey: .autoScroll) ?? d.autoScroll
        autoScrollSpeed =
            try c.decodeIfPresent(Double.self, forKey: .autoScrollSpeed) ?? d.autoScrollSpeed
        tapToToggleBar =
            try c.decodeIfPresent(Bool.self, forKey: .tapToToggleBar) ?? d.tapToToggleBar
        // Saved values are ignored: phones always read full screen.
        containerized = false
        tapToTurn = try c.decodeIfPresent(Bool.self, forKey: .tapToTurn) ?? d.tapToTurn
    }
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
    /// When each position was saved; compared with the server's `updatedAt` on reopen, newer wins.
    var positionDates: [String: Date] = [:]
}

extension ReaderPreferenceDocument {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReaderPreferenceDocument()
        global = try c.decodeIfPresent(MangaReadingSettings.self, forKey: .global) ?? d.global
        behaviour = try c.decodeIfPresent(ReaderBehaviour.self, forKey: .behaviour) ?? d.behaviour
        overrides =
            try c.decodeIfPresent([String: MangaReadingSettings].self, forKey: .overrides) ?? [:]
        presets = try c.decodeIfPresent([MangaReaderPreset].self, forKey: .presets) ?? []
        positions = try c.decodeIfPresent([String: ReaderPosition].self, forKey: .positions) ?? [:]
        bookmarks = try c.decodeIfPresent([String: ReaderPosition].self, forKey: .bookmarks) ?? [:]
        positionDates = try c.decodeIfPresent([String: Date].self, forKey: .positionDates) ?? [:]
    }
}

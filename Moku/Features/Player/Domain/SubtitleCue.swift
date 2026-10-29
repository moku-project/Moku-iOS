import CoreGraphics
import Foundation

struct SubtitleCue: Equatable, Sendable {
    let start: Double
    let end: Double
    let text: String
    /// ASS styling. Desktop renders with libass; iOS draws the same style
    /// fields natively: font, size, weight, slant, colours, outline, alignment
    /// and `\pos`. Animated tags (`\move`, `\t`, karaoke) are not drawn.
    var bold = false
    var italic = false
    /// Primary colour as 0xRRGGBB; nil is white.
    var color: UInt32? = nil
    var position: Position = .bottom
    var horizontal: Horizontal = .center
    /// The style's font, used when iOS has it; otherwise the system font.
    var fontName: String? = nil
    /// Font size as a fraction of the script height (`Fontsize / PlayResY`).
    var size: Double? = nil
    /// Outline colour (0xRRGGBB) and width as a fraction of the script height.
    var outline: UInt32? = nil
    var outlineWidth: Double = 0
    /// `\pos(x, y)` as fractions of the script width and height.
    var anchor: CGPoint? = nil
    /// `\fad(in, out)` in seconds.
    var fadeIn = 0.0
    var fadeOut = 0.0
    /// `\move(x1, y1, x2, y2[, t1, t2])`: `anchor` is the start; times are
    /// seconds after the cue starts, and nil means the whole cue.
    var moveTo: CGPoint? = nil
    var moveTimes: ClosedRange<Double>? = nil

    /// `\alpha` / `\1a` as opacity, 1 being opaque.
    var alpha = 1.0
    /// `\k` karaoke: syllables turn from `secondary` to the primary colour as they are sung.
    var karaoke: [Syllable] = []
    var secondary: UInt32? = nil
    /// `\t(t1, t2, …)` from the line's first override block.
    var transform: Transform? = nil
    /// `\frz` in degrees, counter-clockwise as in ASS; `\fscx` / `\fscy` as factors.
    var rotation = 0.0
    var scaleX = 1.0
    var scaleY = 1.0
    /// `\clip` / `\iclip` rectangle, as fractions of the script size.
    var clip: CGRect? = nil
    var clipInverted = false
    /// A `\p` vector drawing in script fractions; the line is a shape, not text.
    var shape: [ShapeCommand] = []
    /// `\clip` / `\iclip` with a drawing instead of a rectangle.
    var clipShape: [ShapeCommand] = []
    /// `\frx` / `\fry` in degrees.
    var rotationX = 0.0
    var rotationY = 0.0
    /// `\shad` depth and `\4c` colour; depth is a fraction of the script height.
    var shadowDepth = 0.0
    var shadowColor: UInt32? = nil
    /// `\blur` / `\be` strength, as a fraction of the script height.
    var blur = 0.0

    enum ShapeCommand: Equatable, Sendable {
        case move(CGPoint)
        case line(CGPoint)
        case curve(CGPoint, CGPoint, CGPoint)
        case close
    }

    struct Syllable: Equatable, Sendable {
        let text: String
        /// Seconds after the cue starts.
        let start: Double
    }

    struct Transform: Equatable, Sendable {
        /// Seconds after the cue starts; nil end means the whole cue.
        var from = 0.0
        var to: Double?
        var size: Double?
        var color: UInt32?
        var outlineWidth: Double?
        var alpha: Double?
    }

    var isAnimated: Bool { fadeIn > 0 || fadeOut > 0 || moveTo != nil || !karaoke.isEmpty || transform != nil }

    /// How far a `\t` transform has run at `time`, 0…1.
    func transformProgress(at time: Double) -> Double {
        guard let transform else { return 0 }
        let to = transform.to ?? (end - start)
        guard to > transform.from else { return time - start >= to ? 1 : 0 }
        return min(1, max(0, (time - start - transform.from) / (to - transform.from)))
    }

    func size(at time: Double) -> Double? {
        guard let target = transform?.size, let size else { return size }
        return size + (target - size) * transformProgress(at: time)
    }

    func color(at time: Double) -> UInt32? {
        guard let target = transform?.color else { return color }
        return Self.mix(color ?? 0xFFFFFF, target, transformProgress(at: time))
    }

    func outlineWidth(at time: Double) -> Double {
        guard let target = transform?.outlineWidth else { return outlineWidth }
        return outlineWidth + (target - outlineWidth) * transformProgress(at: time)
    }

    func alpha(at time: Double) -> Double {
        guard let target = transform?.alpha else { return alpha }
        return alpha + (target - alpha) * transformProgress(at: time)
    }

    /// Whether karaoke syllable `index` has been sung by `time`.
    func sung(_ index: Int, at time: Double) -> Bool {
        karaoke.indices.contains(index) && time - start >= karaoke[index].start
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * amount).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// Opacity at `time`, from `\fad`.
    func opacity(at time: Double) -> Double {
        var value = 1.0
        if fadeIn > 0 { value = min(value, (time - start) / fadeIn) }
        if fadeOut > 0 { value = min(value, (end - time) / fadeOut) }
        return min(1, max(0, value))
    }

    /// The `\pos` or `\move` point at `time`.
    func anchor(at time: Double) -> CGPoint? {
        guard let anchor, let moveTo else { return anchor }
        let span = moveTimes ?? 0...(end - start)
        let length = span.upperBound - span.lowerBound
        let progress = length > 0 ? min(1, max(0, (time - start - span.lowerBound) / length)) : 1
        return CGPoint(x: anchor.x + (moveTo.x - anchor.x) * progress, y: anchor.y + (moveTo.y - anchor.y) * progress)
    }

    enum Position: Sendable { case bottom, middle, top }
    enum Horizontal: Sendable { case left, center, right }

    static func timestamp(_ value: String) -> Double? {
        let fields = value.replacingOccurrences(of: ",", with: ".")
            .split(separator: ":", omittingEmptySubsequences: false)
        let parts = fields.compactMap { Double($0) }
        guard parts.count == fields.count, (2...3).contains(parts.count),
            parts.allSatisfy({ $0.isFinite && $0 >= 0 })
        else {
            return nil
        }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// VTT/SRT cues; strips presentation markup rather than displaying raw source tags.
    static func parse(_ text: String) -> [SubtitleCue] {
        if text.drop { $0 == "\u{FEFF}" || $0.isWhitespace }.hasPrefix("[Script Info]") { return parseASS(text) }
        return text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n").compactMap { block in
                let lines = block.components(separatedBy: "\n")
                guard let index = lines.firstIndex(where: { $0.contains(" --> ") }) else {
                    return nil
                }
                let times = lines[index].components(separatedBy: " --> ")
                guard times.count == 2, let start = timestamp(times[0]),
                    let endField = times[1].split(separator: " ").first,
                    let end = timestamp(String(endField)), end > start
                else { return nil }
                let caption = lines.dropFirst(index + 1).joined(separator: "\n")
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                return SubtitleCue(start: start, end: end, text: caption)
            }
    }

    // MARK: - ASS / SSA

    private struct ASSStyle {
        var bold = false
        var italic = false
        var color: UInt32?
        var alignment = 2
        var fontName: String?
        var fontSize: Double?
        var outline: UInt32?
        var outlineWidth = 0.0
        var secondary: UInt32?
        var rotation = 0.0
        var scaleX = 1.0
        var scaleY = 1.0
        var shadowDepth = 0.0
        var shadowColor: UInt32?
    }

    static func parseASS(_ text: String) -> [SubtitleCue] {
        var section = ""
        var styleFormat: [String] = []
        var eventFormat: [String] = []
        var styles: [String: ASSStyle] = [:]
        var cues: [SubtitleCue] = []
        // The script's own coordinate space; 384×288 when the header omits it.
        var resX = 384.0, resY = 288.0
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { section = line.lowercased(); continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if section.contains("script info") {
                if key == "playresx", let value = Double(value), value > 0 { resX = value }
                if key == "playresy", let value = Double(value), value > 0 { resY = value }
            } else if section.contains("styles") {
                if key == "format" { styleFormat = fields(value, count: .max).map { $0.lowercased() } }
                if key == "style", !styleFormat.isEmpty {
                    let parts = fields(value, count: styleFormat.count)
                    func field(_ name: String) -> String? { styleFormat.firstIndex(of: name).flatMap { parts.indices.contains($0) ? parts[$0] : nil } }
                    var style = ASSStyle()
                    style.bold = field("bold").map { $0 != "0" } ?? false
                    style.italic = field("italic").map { $0 != "0" } ?? false
                    style.color = field("primarycolour").flatMap(color)
                    style.alignment = field("alignment").flatMap(Int.init) ?? 2
                    style.fontName = field("fontname").flatMap { $0.isEmpty ? nil : $0 }
                    style.fontSize = field("fontsize").flatMap(Double.init)
                    style.outline = field("outlinecolour").flatMap(color)
                    style.outlineWidth = field("outline").flatMap(Double.init) ?? 0
                    style.secondary = field("secondarycolour").flatMap(color)
                    style.rotation = field("angle").flatMap(Double.init) ?? 0
                    style.scaleX = (field("scalex").flatMap(Double.init) ?? 100) / 100
                    style.scaleY = (field("scaley").flatMap(Double.init) ?? 100) / 100
                    style.shadowDepth = field("shadow").flatMap(Double.init) ?? 0
                    style.shadowColor = field("backcolour").flatMap(color)
                    styles[field("name") ?? "Default"] = style
                }
            } else if section.contains("events") {
                if key == "format" { eventFormat = fields(value, count: .max).map { $0.lowercased() } }
                guard key == "dialogue", !eventFormat.isEmpty else { continue }
                let parts = fields(value, count: eventFormat.count)
                func field(_ name: String) -> String? { eventFormat.firstIndex(of: name).flatMap { parts.indices.contains($0) ? parts[$0] : nil } }
                guard let start = field("start").flatMap(timestamp), let end = field("end").flatMap(timestamp), end > start,
                      var body = field("text") else { continue }
                var style = styles[field("style") ?? ""] ?? styles["Default"] ?? ASSStyle()
                var anchor: CGPoint?, moveTo: CGPoint?, moveTimes: ClosedRange<Double>?
                var fadeIn = 0.0, fadeOut = 0.0, alpha = 1.0
                var transform: Transform?
                var clip: CGRect?, clipInverted = false, drawingLevel = 0
                var clipShape: [ShapeCommand] = []
                var rotationX = 0.0, rotationY = 0.0, blur = 0.0
                // Overrides in the first {…} block style the whole line.
                if body.hasPrefix("{"), let close = body.firstIndex(of: "}") {
                    var tags = String(body[body.index(after: body.startIndex)..<close])
                    // \t(…) holds target values; read it first so its tags aren't taken as static.
                    if let value = tag(tags, #"\\t\(([^)]*)\)"#) {
                        transform = parseTransform(value, resY: resY)
                        tags = tags.replacingOccurrences(of: #"\\t\([^)]*\)"#, with: "", options: .regularExpression)
                    }
                    if let value = tag(tags, #"\\(?:alpha|1a)(&H[0-9A-Fa-f]+&?)"#).flatMap(opacity) { alpha = value }
                    if let value = tag(tags, #"\\frz?(-?[0-9.]+)"#).flatMap(Double.init) { style.rotation = value }
                    if let value = tag(tags, #"\\fscx([0-9.]+)"#).flatMap(Double.init) { style.scaleX = value / 100 }
                    if let value = tag(tags, #"\\fscy([0-9.]+)"#).flatMap(Double.init) { style.scaleY = value / 100 }
                    if let value = tag(tags, #"\\frx(-?[0-9.]+)"#).flatMap(Double.init) { rotationX = value }
                    if let value = tag(tags, #"\\fry(-?[0-9.]+)"#).flatMap(Double.init) { rotationY = value }
                    if let value = tag(tags, #"\\shad([0-9.]+)"#).flatMap(Double.init) { style.shadowDepth = value }
                    if let value = tag(tags, #"\\4c(&H[0-9A-Fa-f]+&?)"#).flatMap(color) { style.shadowColor = value }
                    if let value = tag(tags, #"\\blur([0-9.]+)"#).flatMap(Double.init) { blur = value / resY }
                    if blur == 0, let value = tag(tags, #"\\be([0-9.]+)"#).flatMap(Double.init) { blur = value / resY }
                    if let value = tag(tags, #"\\(i?clip)\(([^)]*)\)"#), let inner = tag(tags, #"\\i?clip\(([^)]*)\)"#) {
                        let box = numbers(inner)
                        // A drawing clip: \clip([scale,] m … ).
                        if box.count != 4, let start = inner.firstIndex(where: { $0.isLetter }) {
                            let level = Int(inner[..<start].trimmingCharacters(in: CharacterSet(charactersIn: ", ")).trimmingCharacters(in: .whitespaces)) ?? 1
                            clipShape = Self.shape(String(inner[start...]), scale: pow(2, Double(max(1, level) - 1)), resX: resX, resY: resY)
                            clipInverted = value == "iclip"
                        }
                        if box.count == 4 {
                            clip = CGRect(x: min(box[0], box[2]) / resX, y: min(box[1], box[3]) / resY,
                                          width: abs(box[2] - box[0]) / resX, height: abs(box[3] - box[1]) / resY)
                            clipInverted = value == "iclip"
                        }
                    }
                    if let value = tag(tags, #"\\p([0-9]+)"#).flatMap(Int.init) { drawingLevel = value }
                    if let value = tag(tags, #"\\an([1-9])"#).flatMap(Int.init) { style.alignment = value }
                    if let value = tag(tags, #"\\b(\d+)"#) { style.bold = value != "0" }
                    if let value = tag(tags, #"\\i([01])"#) { style.italic = value == "1" }
                    if let value = tag(tags, #"\\1?c(&H[0-9A-Fa-f]+&?)"#).flatMap(color) { style.color = value }
                    if let value = tag(tags, #"\\3c(&H[0-9A-Fa-f]+&?)"#).flatMap(color) { style.outline = value }
                    if let value = tag(tags, #"\\fs([0-9.]+)"#).flatMap(Double.init) { style.fontSize = value }
                    if let value = tag(tags, #"\\bord([0-9.]+)"#).flatMap(Double.init) { style.outlineWidth = value }
                    if let value = tag(tags, #"\\fn([^\\}]+)"#) { style.fontName = value }
                    if let value = tag(tags, #"\\pos\(([^)]*)\)"#) {
                        let point = numbers(value)
                        if point.count == 2 { anchor = CGPoint(x: point[0] / resX, y: point[1] / resY) }
                    }
                    if let value = tag(tags, #"\\fade?\(([^)]*)\)"#) {
                        let times = numbers(value)
                        if times.count == 2 { fadeIn = times[0] / 1000; fadeOut = times[1] / 1000 }
                    }
                    if let value = tag(tags, #"\\move\(([^)]*)\)"#) {
                        let point = numbers(value)
                        if point.count >= 4 {
                            anchor = CGPoint(x: point[0] / resX, y: point[1] / resY)
                            moveTo = CGPoint(x: point[2] / resX, y: point[3] / resY)
                            if point.count == 6, point[5] > point[4] { moveTimes = point[4] / 1000...point[5] / 1000 }
                        }
                    }
                }
                // Vector drawings: coordinates are divided by 2^(level - 1).
                let shape = drawingLevel > 0
                    ? Self.shape(Self.plain(body), scale: pow(2, Double(drawingLevel - 1)), resX: resX, resY: resY) : []
                if drawingLevel > 0 && shape.isEmpty { continue }
                let karaoke = drawingLevel > 0 ? [] : Self.karaoke(body)
                body = drawingLevel > 0 ? "" : Self.plain(body).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty || !shape.isEmpty else { continue }
                let position: Position = style.alignment >= 7 ? .top : style.alignment >= 4 ? .middle : .bottom
                let column = style.alignment % 3
                cues.append(SubtitleCue(
                    start: start, end: end, text: body, bold: style.bold, italic: style.italic,
                    color: style.color == 0xFFFFFF ? nil : style.color, position: position,
                    horizontal: column == 1 ? .left : column == 0 ? .right : .center,
                    fontName: style.fontName, size: style.fontSize.map { $0 / resY },
                    outline: style.outlineWidth > 0 ? style.outline ?? 0 : nil,
                    outlineWidth: style.outlineWidth / resY, anchor: anchor,
                    fadeIn: fadeIn, fadeOut: fadeOut, moveTo: moveTo, moveTimes: moveTimes,
                    alpha: alpha, karaoke: karaoke, secondary: style.secondary, transform: transform,
                    rotation: style.rotation, scaleX: style.scaleX, scaleY: style.scaleY,
                    clip: clip, clipInverted: clipInverted, shape: shape, clipShape: clipShape,
                    rotationX: rotationX, rotationY: rotationY,
                    shadowDepth: style.shadowDepth / resY, shadowColor: style.shadowColor, blur: blur))
            }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// Override blocks removed and ASS line breaks turned into text.
    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: " ")
    }

    /// ASS drawing commands (`m`, `n`, `l`, `b`, `c`) in script fractions.
    /// Splines (`s`, `p`) are drawn as straight lines through their points.
    private static func shape(_ text: String, scale: Double, resX: Double, resY: Double) -> [ShapeCommand] {
        var commands: [ShapeCommand] = []
        var mode: Character = "m"
        var pending: [Double] = []
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x / scale / resX, y: y / scale / resY) }
        func flush() {
            switch mode {
            case "m", "n":
                while pending.count >= 2 { commands.append(.move(point(pending[0], pending[1]))); pending.removeFirst(2); mode = "l" }
            case "b":
                while pending.count >= 6 {
                    commands.append(.curve(point(pending[0], pending[1]), point(pending[2], pending[3]), point(pending[4], pending[5])))
                    pending.removeFirst(6)
                }
            default:
                while pending.count >= 2 { commands.append(.line(point(pending[0], pending[1]))); pending.removeFirst(2) }
            }
        }
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            if let value = Double(token) {
                pending.append(value)
                flush()
            } else if let letter = token.lowercased().first, "mnlbspc".contains(letter) {
                pending = []
                if letter == "c" { commands.append(.close) } else { mode = letter == "s" || letter == "p" ? "l" : letter }
            }
        }
        return commands.contains { if case .move = $0 { false } else { true } } ? commands : []
    }

    /// `\k`, `\K`, `\kf` and `\ko` syllables (durations in centiseconds), or none.
    private static func karaoke(_ body: String) -> [Syllable] {
        guard body.range(of: #"\\[kK][fo]?\d"#, options: .regularExpression) != nil,
              let blocks = try? NSRegularExpression(pattern: #"\{([^}]*)\}"#) else { return [] }
        var syllables: [Syllable] = []
        var clock = 0.0, pending = 0.0
        var cursor = body.startIndex
        func flush(_ text: Substring) {
            let segment = plain(String(text))
            guard !segment.isEmpty else { return }
            syllables.append(Syllable(text: segment, start: clock))
            clock += pending
            pending = 0
        }
        for match in blocks.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let whole = Range(match.range, in: body), let inner = Range(match.range(at: 1), in: body) else { continue }
            flush(body[cursor..<whole.lowerBound])
            if let value = tag(String(body[inner]), #"\\[kK][fo]?(\d+)"#).flatMap(Double.init) { pending = value / 100 }
            cursor = whole.upperBound
        }
        flush(body[cursor...])
        // Trim the outer whitespace the way the line itself is trimmed.
        if let first = syllables.first {
            syllables[0] = Syllable(text: String(first.text.drop { $0.isWhitespace || $0.isNewline }), start: first.start)
        }
        if let last = syllables.last {
            let trimmed = String(last.text.reversed().drop { $0.isWhitespace || $0.isNewline }.reversed())
            syllables[syllables.count - 1] = Syllable(text: trimmed, start: last.start)
        }
        return syllables.filter { !$0.text.isEmpty }
    }

    /// `\t([t1, t2,] [accel,] tags)`: times in ms, then the target tags.
    private static func parseTransform(_ value: String, resY: Double) -> Transform? {
        guard let slash = value.firstIndex(of: "\\") else { return nil }
        let times = numbers(String(value[..<slash]))
        let tags = String(value[slash...])
        var transform = Transform()
        if times.count >= 2 { transform.from = times[0] / 1000; transform.to = times[1] / 1000 }
        transform.size = tag(tags, #"\\fs([0-9.]+)"#).flatMap(Double.init).map { $0 / resY }
        transform.color = tag(tags, #"\\1?c(&H[0-9A-Fa-f]+&?)"#).flatMap(color)
        transform.outlineWidth = tag(tags, #"\\bord([0-9.]+)"#).flatMap(Double.init).map { $0 / resY }
        transform.alpha = tag(tags, #"\\(?:alpha|1a)(&H[0-9A-Fa-f]+&?)"#).flatMap(opacity)
        let animates = transform.size != nil || transform.color != nil || transform.outlineWidth != nil || transform.alpha != nil
        return animates ? transform : nil
    }

    /// `&HAA&` alpha (00 opaque, FF clear) as opacity.
    private static func opacity(_ value: String) -> Double? {
        let hex = value.uppercased().replacingOccurrences(of: "&H", with: "").replacingOccurrences(of: "&", with: "")
        guard let raw = UInt32(hex, radix: 16) else { return nil }
        return 1 - Double(raw & 0xFF) / 255
    }

    private static func numbers(_ value: String) -> [Double] {
        value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Comma-separated fields where the last one keeps its commas (dialogue text).
    private static func fields(_ value: String, count: Int) -> [String] {
        value.split(separator: ",", maxSplits: max(0, count - 1), omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func tag(_ tags: String, _ pattern: String) -> String? {
        guard let match = tags.range(of: pattern, options: .regularExpression) else { return nil }
        let found = String(tags[match])
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: found, range: NSRange(found.startIndex..., in: found)),
              let range = Range(result.range(at: 1), in: found) else { return nil }
        return String(found[range])
    }

    /// `&HAABBGGRR` or `&HBBGGRR&` → 0xRRGGBB.
    private static func color(_ value: String) -> UInt32? {
        let hex = value.uppercased().replacingOccurrences(of: "&H", with: "").replacingOccurrences(of: "&", with: "")
        guard let raw = UInt32(hex, radix: 16) else { return nil }
        let blue = (raw >> 16) & 0xFF, green = (raw >> 8) & 0xFF, red = raw & 0xFF
        return (red << 16) | (green << 8) | blue
    }
}

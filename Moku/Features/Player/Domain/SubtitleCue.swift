import Foundation

struct SubtitleCue: Equatable, Sendable {
    let start: Double
    let end: Double
    let text: String
    /// ASS styling: desktop renders these with libass; iOS keeps the parts
    /// that matter for reading (weight, slant, colour and screen position).
    var bold = false
    var italic = false
    /// Primary colour as 0xRRGGBB; nil is white.
    var color: UInt32? = nil
    var position: Position = .bottom

    enum Position: Sendable { case bottom, middle, top }

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
    }

    static func parseASS(_ text: String) -> [SubtitleCue] {
        var section = ""
        var styleFormat: [String] = []
        var eventFormat: [String] = []
        var styles: [String: ASSStyle] = [:]
        var cues: [SubtitleCue] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { section = line.lowercased(); continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if section.contains("styles") {
                if key == "format" { styleFormat = fields(value, count: .max).map { $0.lowercased() } }
                if key == "style", !styleFormat.isEmpty {
                    let parts = fields(value, count: styleFormat.count)
                    func field(_ name: String) -> String? { styleFormat.firstIndex(of: name).flatMap { parts.indices.contains($0) ? parts[$0] : nil } }
                    var style = ASSStyle()
                    style.bold = field("bold").map { $0 != "0" } ?? false
                    style.italic = field("italic").map { $0 != "0" } ?? false
                    style.color = field("primarycolour").flatMap(color)
                    style.alignment = field("alignment").flatMap(Int.init) ?? 2
                    styles[field("name") ?? "Default"] = style
                }
            } else if section.contains("events") {
                if key == "format" { eventFormat = fields(value, count: .max).map { $0.lowercased() } }
                guard key == "dialogue", !eventFormat.isEmpty else { continue }
                let parts = fields(value, count: eventFormat.count)
                func field(_ name: String) -> String? { eventFormat.firstIndex(of: name).flatMap { parts.indices.contains($0) ? parts[$0] : nil } }
                guard let start = field("start").flatMap(timestamp), let end = field("end").flatMap(timestamp), end > start,
                      var body = field("text") else { continue }
                // Vector drawings ({\p1}) are shapes, not text.
                if body.range(of: #"\\p[1-9]"#, options: .regularExpression) != nil { continue }
                var style = styles[field("style") ?? ""] ?? styles["Default"] ?? ASSStyle()
                // Overrides in the first {…} block style the whole line.
                if body.hasPrefix("{"), let close = body.firstIndex(of: "}") {
                    let tags = String(body[body.index(after: body.startIndex)..<close])
                    if let value = tag(tags, #"\\an([1-9])"#).flatMap(Int.init) { style.alignment = value }
                    if let value = tag(tags, #"\\b(\d+)"#) { style.bold = value != "0" }
                    if let value = tag(tags, #"\\i([01])"#) { style.italic = value == "1" }
                    if let value = tag(tags, #"\\1?c(&H[0-9A-Fa-f]+&?)"#).flatMap(color) { style.color = value }
                }
                body = body.replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\\h", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { continue }
                let position: Position = style.alignment >= 7 ? .top : style.alignment >= 4 ? .middle : .bottom
                cues.append(SubtitleCue(start: start, end: end, text: body, bold: style.bold, italic: style.italic,
                                        color: style.color == 0xFFFFFF ? nil : style.color, position: position))
            }
        }
        return cues.sorted { $0.start < $1.start }
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

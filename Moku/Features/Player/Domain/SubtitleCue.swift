import Foundation

struct SubtitleCue: Equatable, Sendable {
    let start: Double
    let end: Double
    let text: String

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
        text.replacingOccurrences(of: "\r\n", with: "\n")
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
}

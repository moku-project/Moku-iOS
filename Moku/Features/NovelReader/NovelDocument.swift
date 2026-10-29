import Foundation

/// A chapter as typeset blocks. The server already sanitizes novel HTML, so this
/// keeps only structure (paragraphs, headings, rules) and inline emphasis, and
/// never needs WebKit, which would block the main thread for long chapters.
struct NovelDocument: Sendable, Equatable {
    enum Block: Sendable, Equatable {
        case paragraph(AttributedString)
        case heading(AttributedString)
        case rule
    }

    var blocks: [Block]
    var wordCount: Int

    nonisolated static func parse(_ text: String, isHTML: Bool) -> NovelDocument {
        let blocks = isHTML ? html(text) : plain(text)
        let words = blocks.reduce(0) { total, block in
            switch block {
            case .paragraph(let value), .heading(let value):
                total + String(value.characters).split(whereSeparator: \.isWhitespace).count
            case .rule: total
            }
        }
        return NovelDocument(blocks: blocks, wordCount: words)
    }

    private nonisolated static func plain(_ text: String) -> [Block] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { .paragraph(AttributedString($0)) }
    }

    private nonisolated static func html(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var current = AttributedString()
        var heading = false
        var bold = 0, italic = 0
        var skipping: String?

        func flush() {
            var text = current
            // Collapse whitespace runs that HTML would not render.
            let trimmed = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                while let first = text.characters.first, first.isWhitespace { text.removeSubrange(text.startIndex..<text.index(afterCharacter: text.startIndex)) }
                while let last = text.characters.last, last.isWhitespace { text.removeSubrange(text.index(beforeCharacter: text.endIndex)..<text.endIndex) }
                blocks.append(heading ? .heading(text) : .paragraph(text))
            }
            current = AttributedString()
        }

        func append(_ raw: Substring) {
            let collapsed = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            guard !collapsed.isEmpty else { return }
            if collapsed == " ", current.characters.last?.isWhitespace ?? true { return }
            var run = AttributedString(decodeEntities(collapsed))
            var intent: InlinePresentationIntent = []
            if bold > 0 { intent.insert(.stronglyEmphasized) }
            if italic > 0 { intent.insert(.emphasized) }
            if !intent.isEmpty { run.inlinePresentationIntent = intent }
            current += run
        }

        var index = source.startIndex
        while index < source.endIndex {
            guard let open = source[index...].firstIndex(of: "<") else {
                if skipping == nil { append(source[index...]) }
                break
            }
            if skipping == nil { append(source[index..<open]) }
            guard let close = source[open...].firstIndex(of: ">") else { break }
            let tag = source[source.index(after: open)..<close]
            index = source.index(after: close)
            let closing = tag.hasPrefix("/")
            let name = tag.drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }.lowercased()
            if let skip = skipping {
                if closing && name == skip { skipping = nil }
                continue
            }
            switch name {
            case "script", "style", "head", "title":
                if !closing && !tag.hasSuffix("/") { skipping = name }
            case "p", "div", "li", "blockquote", "section", "article", "tr":
                flush()
            case "br":
                flush()
            case "h1", "h2", "h3", "h4", "h5", "h6":
                flush()
                heading = !closing
            case "hr":
                flush()
                blocks.append(.rule)
            case "b", "strong":
                bold = max(0, bold + (closing ? -1 : 1))
            case "i", "em", "cite":
                italic = max(0, italic + (closing ? -1 : 1))
            default:
                break
            }
        }
        flush()
        return blocks
    }

    private nonisolated static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
            "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’",
            "ldquo": "“", "rdquo": "”", "middot": "·", "copy": "©",
        ]
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&", let semicolon = text[index...].prefix(10).firstIndex(of: ";") {
                let entity = text[text.index(after: index)..<semicolon]
                var replacement: String?
                if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                    replacement = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if entity.hasPrefix("#") {
                    replacement = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    replacement = named[String(entity)]
                }
                if let replacement {
                    result += replacement
                    index = text.index(after: semicolon)
                    continue
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }
}

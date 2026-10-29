import CoreText
import Foundation
import UIKit

/// Fonts embedded in an ASS file's `[Fonts]` section. Desktop's libass loads
/// them; here they are decoded and registered for the app, so the script's
/// style font names resolve.
enum SubtitleFonts {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var registered: Set<String> = []

    /// Registers every embedded font once; returns the file names newly added.
    @discardableResult
    static func register(in script: String) -> [String] {
        var added: [String] = []
        for (name, data) in embedded(in: script) {
            lock.lock()
            let fresh = registered.insert(name).inserted
            lock.unlock()
            guard fresh, let provider = CGDataProvider(data: data as CFData),
                  let font = CGFont(provider) else { continue }
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterGraphicsFont(font, &error) { added.append(name) }
        }
        return added
    }

    /// `fontname: file.ttf` entries and their decoded bytes.
    static func embedded(in script: String) -> [(name: String, data: Data)] {
        var fonts: [(String, Data)] = []
        var inFonts = false
        var name: String?
        var encoded = ""
        func finish() {
            if let name, let data = decode(encoded), !data.isEmpty { fonts.append((name, data)) }
            name = nil
            encoded = ""
        }
        for raw in script.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                finish()
                inFonts = line.lowercased() == "[fonts]"
                continue
            }
            guard inFonts, !line.isEmpty else { continue }
            if line.lowercased().hasPrefix("fontname:") {
                finish()
                name = line.dropFirst("fontname:".count).trimmingCharacters(in: .whitespaces)
            } else if name != nil {
                encoded += line
            }
        }
        finish()
        return fonts
    }

    /// SSA uuencoding: each character is 33 + six bits; four characters make
    /// three bytes, and a short final group makes one or two.
    static func decode(_ text: String) -> Data? {
        let values = text.unicodeScalars.map { Int($0.value) - 33 }
        guard values.allSatisfy({ (0...63).contains($0) }) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(values.count * 3 / 4)
        var index = 0
        while index < values.count {
            let group = Array(values[index..<min(index + 4, values.count)])
            let a = group[0], b = group.count > 1 ? group[1] : 0
            let c = group.count > 2 ? group[2] : 0, d = group.count > 3 ? group[3] : 0
            if group.count >= 2 { bytes.append(UInt8((a << 2 | b >> 4) & 0xFF)) }
            if group.count >= 3 { bytes.append(UInt8(((b & 0xF) << 4 | c >> 2) & 0xFF)) }
            if group.count == 4 { bytes.append(UInt8(((c & 0x3) << 6 | d) & 0xFF)) }
            index += 4
        }
        return Data(bytes)
    }

    /// A font by PostScript or full name, else by family (how ASS styles name them).
    static func font(named name: String, size: CGFloat) -> UIFont? {
        if let font = UIFont(name: name, size: size) { return font }
        let descriptor = UIFontDescriptor(fontAttributes: [.family: name])
        let matches = descriptor.matchingFontDescriptors(withMandatoryKeys: [.family])
        return matches.first.map { UIFont(descriptor: $0, size: size) }
    }
}

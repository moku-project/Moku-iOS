import Foundation

enum GeneralPreferences {
    static func clampedScale(_ value: Double) -> Double {
        value.isFinite ? min(200, max(50, value)) : 100
    }
    static func canonicalLanguage(_ value: String) -> String {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "_", with: "-")
        return ["", "*", "all", "multi", "mul", "any"].contains(code) ? "all" : code
    }
    static func languageName(_ value: String) -> String {
        value == "all"
            ? "All languages" : (Locale.current.localizedString(forIdentifier: value) ?? value)
    }
    /// Matches the desktop language choices and preserves previously saved source codes.
    static func languageOptions(including current: String) -> [(String, String)] {
        var codes: Set<String> = [
            "en", "ja", "ko", "zh", "zh-hans", "zh-hant", "es", "es-419", "pt", "pt-br",
            "pt-pt", "fr", "de", "it", "ru", "uk", "pl", "nl", "id", "vi", "th", "fil",
            "ms", "ar", "fa", "he", "tr", "hi", "bn", "ta", "te", "el", "cs", "sk", "hu",
            "ro", "bg", "sr", "hr", "sv", "fi", "da", "no", "nb", "nn", "ca", "eu", "gl",
        ]
        let saved = canonicalLanguage(current)
        if saved != "all" { codes.insert(saved) }
        let choices = codes.map { ($0, languageName($0)) }.sorted {
            $0.1.localizedStandardCompare($1.1) == .orderedAscending
        }
        return [("all", "All languages")] + choices
    }

    static func timeoutLabel(_ minutes: Int) -> String {
        minutes == 0 ? "Never" : minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

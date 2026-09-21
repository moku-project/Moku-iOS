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
    static func timeoutLabel(_ minutes: Int) -> String {
        minutes == 0 ? "Never" : minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

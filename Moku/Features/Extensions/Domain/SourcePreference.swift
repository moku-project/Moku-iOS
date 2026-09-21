import Foundation

struct SourcePreference: Decodable, Identifiable, Sendable {
    let key: String
    let title: String
    let summary: String
    let type: String
    let entries: [String]
    let entryValues: [String]
    let currentValue: String
    let defaultValue: String
    var id: String { key }
    var displaySummary: String {
        let label: String
        if let index = entryValues.firstIndex(of: currentValue), index < entries.count {
            label = entries[index]
        } else {
            label = currentValue
        }
        return summary.replacingOccurrences(of: "%s", with: label)
    }
}

struct ExtensionPage: Decodable, Sendable {
    let items: [SourceExtension]
    let total: Int
    let languages: [String]
}

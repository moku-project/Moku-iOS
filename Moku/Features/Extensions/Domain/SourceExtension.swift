import Foundation

struct ExtensionRepositoryInfo: Decodable, Identifiable, Sendable {
    let id: String
    let name: String?
    let indexUrl: String
    var title: String { name?.isEmpty == false ? name! : indexUrl }
}

struct SourceExtension: Decodable, Identifiable, Sendable {
    let id: String
    let repositoryId: String
    let packageName: String
    let displayName: String
    let version: String
    let installedVersion: String?
    let lang: String
    let contentType: String
    let installed: Bool
    let enabled: Bool
    let needsUpdate: Bool?
    let isNsfw: Bool
    var iconUrl: String? = nil
    var iconURL: URL? { BackendAPI.coverURL(iconUrl) }
    var subtitle: String {
        "\(GeneralPreferences.languageName(GeneralPreferences.canonicalLanguage(lang))) · \(contentType.capitalized) · v\(installedVersion ?? version)"
    }
    var media: ContentMode {
        switch contentType {
        case "ANIME": .anime
        case "NOVEL": .novels
        default: .manga
        }
    }
}

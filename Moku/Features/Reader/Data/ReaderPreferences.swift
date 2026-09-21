import Foundation
import Observation

@MainActor @Observable final class ReaderPreferences {
    private let defaults: UserDefaults
    private let key = "reader.preferences.v1"
    var document: ReaderPreferenceDocument {
        didSet {
            if let data = try? JSONEncoder().encode(document) { defaults.set(data, forKey: key) }
        }
    }
    init(defaults: UserDefaults) {
        self.defaults = defaults
        document =
            defaults.data(forKey: key).flatMap {
                try? JSONDecoder().decode(ReaderPreferenceDocument.self, from: $0)
            } ?? ReaderPreferenceDocument()
    }
    func settings(for mediaID: String?) -> MangaReadingSettings {
        mediaID.flatMap { document.overrides[$0] } ?? document.global
    }
    func set(_ settings: MangaReadingSettings, for mediaID: String?) {
        if let mediaID, document.overrides[mediaID] != nil {
            document.overrides[mediaID] = settings
        } else {
            document.global = settings
        }
    }
    func toggleOverride(_ mediaID: String) {
        if document.overrides[mediaID] == nil {
            document.overrides[mediaID] = document.global
        } else {
            document.overrides.removeValue(forKey: mediaID)
        }
    }
    func savePreset(_ name: String, mediaID: String?) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        document.presets.append(MangaReaderPreset(name: name, settings: settings(for: mediaID)))
    }
}

/// Page numbers are one-based, as on desktop. Auto uses double pages when the viewport ratio exceeds 1.25.

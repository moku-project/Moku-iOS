import Foundation
import Observation

@MainActor @Observable final class ReaderPreferences {
    private let defaults: UserDefaults
    private let key = "reader.preferences.v1"
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    var document: ReaderPreferenceDocument {
        didSet {
            scheduleSave()

        }
    }
    init(defaults: UserDefaults) {
        self.defaults = defaults
        document =
            defaults.data(forKey: key).flatMap {
                try? JSONDecoder().decode(ReaderPreferenceDocument.self, from: $0)
            } ?? ReaderPreferenceDocument()
    }
    // Page turns can arrive faster than storage. Encode only the latest snapshot,
    // off the UI executor, and retain an explicit durability boundary on dismissal.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = document
        let defaults = defaults
        let key = key
        saveTask = Task {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            let data = await Task.detached(priority: .utility) {
                try? JSONEncoder().encode(snapshot)
            }.value
            guard !Task.isCancelled, let data else { return }
            defaults.set(data, forKey: key)
        }
    }

    func flush() async { await saveTask?.value }

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

import SwiftUI

/// Form sections choosing what to import and which source to match titles on.
struct ImportSetup: View {
    @Bindable var model: TrackingViewModel
    private let lists = [
        ("CURRENT", "Reading"), ("PLANNING", "Planning"), ("COMPLETED", "Completed"),
        ("PAUSED", "Paused"), ("DROPPED", "Dropped"), ("REPEATING", "Repeating"),
    ]

    var body: some View {
        Group {
            Section {
                Picker("Media", selection: $model.media) {
                    Text("Manga").tag(ContentMode.manga)
                    Text("Anime").tag(ContentMode.anime)
                }
                .pickerStyle(.segmented)
                .onChange(of: model.media) { _, _ in model.sourceID = nil }
            }
            Section {
                ForEach(lists, id: \.0) { key, label in
                    Toggle(
                        model.media == .anime && key == "CURRENT" ? "Watching" : label,
                        isOn: Binding(
                            get: { model.statuses.contains(key) },
                            set: { selected in
                                if selected {
                                    model.statuses.insert(key)
                                } else {
                                    model.statuses.remove(key)
                                }
                            }))
                }
            } header: {
                Text("Lists")
            } footer: {
                if model.statuses.isEmpty { Text("Choose at least one list.") }
            }
            Section {
                Picker("Language", selection: $model.language) {
                    Text("All Languages").tag(String?.none)
                    ForEach(
                        Array(Set(model.sources.filter { $0.media == model.media }.map(\.language)))
                            .filter { $0 != "all" }.sorted(), id: \.self
                    ) { language in
                        Text(Locale.current.localizedString(forLanguageCode: language) ?? language)
                            .tag(Optional(language))
                    }
                }
                .onChange(of: model.language) { _, _ in model.sourceID = nil }
                Picker("Source", selection: $model.sourceID) {
                    Text("Without a Source").tag(String?.none)
                    ForEach(model.availableSources) { source in
                        Text(source.name).tag(Optional(source.id))
                    }
                }
            } header: {
                Text("Match on")
            } footer: {
                Text(
                    "With a source, chapters are ready to read right away."
                )
            }
            if model.working {
                Section { LabeledContent("Loading list…") { ProgressView() } }
            }
        }
        .disabled(model.working)
    }
}

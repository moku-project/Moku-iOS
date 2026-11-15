import SwiftUI

/// Search filters and sort as a grouped form; edits `model.draft`, which the presenting sheet applies or cancels.
struct SearchOptionsView: View {
    @Bindable var model: SearchViewModel
    /// Kept for source compatibility; the presenting sheet owns the title.
    var showsTitle = true
    @State private var genreQuery = ""
    private let genres = [
        "Action", "Adventure", "Comedy", "Drama", "Fantasy", "Romance", "Sci-Fi",
        "Slice of Life", "Horror", "Mystery", "Thriller", "Sports", "Supernatural",
        "Mecha", "Historical", "Psychological", "School Life", "Shounen", "Seinen",
        "Josei", "Shoujo", "Isekai", "Martial Arts", "Magic", "Music", "Cooking",
        "Medical", "Military", "Harem", "Ecchi",
    ]
    private var matchingGenres: [String] {
        genres.filter { genreQuery.isEmpty || $0.localizedCaseInsensitiveContains(genreQuery) }
    }

    @AppStorage("preferences.language") private var preferredLanguage = "all"

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $model.draft.media) {
                    ForEach(ContentMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("search.filters.mode")
                .onChange(of: model.draft.media) { _, _ in model.validateSource() }
            }

            Section("Sort by") {
                Picker("Sort by", selection: $model.draft.sort) {
                    ForEach(SearchOptions.Sort.allCases) { sort in
                        Label(sort.rawValue, systemImage: sortSymbol(sort)).tag(sort)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            if !model.isLibrary {
                Section("Search by") {
                    Picker("Search by", selection: $model.draft.method) {
                        ForEach(SearchOptions.Method.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    Toggle("Hide titles with no chapters", isOn: $model.draft.hidesEmpty)
                }

                Section("Language") {
                    Picker("Language", selection: $model.draft.language) {
                        Text("All languages").tag(String?.none)
                        ForEach(model.languages, id: \.self) { language in
                            // Desktop marks the preferred source language.
                            Text(
                                (Locale.current.localizedString(forLanguageCode: language) ?? language)
                                    + (language == preferredLanguage ? " · Preferred" : "")
                            )
                            .tag(String?.some(language))
                        }
                    }
                    .onChange(of: model.draft.language) { _, _ in model.validateSource() }
                }
            }

            Section {
                checkRow("All sources", selected: model.draft.sourceID == nil) {
                    model.draft.sourceID = nil
                }
                if model.sourcesAreLoading {
                    HStack {
                        ProgressView()
                        Text("Loading sources…").foregroundStyle(.secondary)
                    }
                } else if let message = model.sourceMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Button("Reload sources") { Task { await model.loadSources() } }
                } else if model.visibleSources.isEmpty {
                    Text("No sources match these filters.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(model.visibleSources) { source in
                        checkRow(
                            source.name, systemImage: source.isPinned ? "pin.fill" : nil,
                            selected: model.draft.sourceID == source.id
                        ) {
                            model.draft.sourceID = source.id
                        }
                        .contextMenu {
                            Button(
                                source.isPinned ? "Unpin Source" : "Pin Source",
                                systemImage: source.isPinned ? "pin.slash" : "pin"
                            ) {
                                SourcePins.toggle(source.id)
                                Task { await model.loadSources() }
                            }
                        }
                    }
                }
            } header: {
                Text("Sources")
            } footer: {
                if !model.canApply {
                    Text("Choose a source for source search.")
                }
            }

            if !model.isLibrary {
                Section {
                    TextField("Find a genre", text: $genreQuery)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Find a genre")
                    ForEach(matchingGenres, id: \.self) { genre in
                        checkRow(genre, selected: model.draft.genres.contains(genre)) {
                            if model.draft.genres.contains(genre) {
                                model.draft.genres.remove(genre)
                            } else {
                                model.draft.genres.insert(genre)
                            }
                        }
                    }
                } header: {
                    Text("Genres")
                }

                Section("Match genres") {
                    Picker("Match genres", selection: $model.draft.match) {
                        ForEach(SearchOptions.Match.allCases) { match in
                            Text(match.rawValue).tag(match)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section("Status") {
                    checkRow("Any status", selected: model.draft.statuses.isEmpty) {
                        model.draft.statuses = []
                    }
                    ForEach(SearchOptions.Status.allCases.filter { $0 != .any }) { status in
                        checkRow(
                            status.rawValue, selected: model.draft.statuses.contains(status)
                        ) {
                            if model.draft.statuses.contains(status) {
                                model.draft.statuses.remove(status)
                            } else {
                                model.draft.statuses.insert(status)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func checkRow(
        _ title: String, systemImage: String? = nil, selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(NavigationStyle.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sortSymbol(_ sort: SearchOptions.Sort) -> String {
        switch sort {
        case .sourceOrder: "list.number"
        case .titleAscending: "arrow.up"
        case .titleDescending: "arrow.down"
        }
    }
}

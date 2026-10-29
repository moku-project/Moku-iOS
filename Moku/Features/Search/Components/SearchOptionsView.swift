import SwiftUI

struct SearchOptionsView: View {
    @Bindable var model: SearchViewModel
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
        VStack(alignment: .leading, spacing: 18) {
            if showsTitle { Text("Filters").font(.title2.bold()) }
            section("Sort by") {
                ForEach(SearchOptions.Sort.allCases) { sort in
                    choice(
                        sort.rawValue, symbol: sortSymbol(sort), selected: model.draft.sort == sort
                    ) {
                        model.draft.sort = sort
                    }
                }
            }
            if !model.isLibrary {
                section("Search by") {
                    ForEach(SearchOptions.Method.allCases) { method in
                        choice(
                            method.rawValue, symbol: methodSymbol(method),
                            selected: model.draft.method == method
                        ) {
                            model.draft.method = method
                        }
                    }
                }
            }
            ModeTabs(mode: $model.draft.media, prefix: "search.filters") {
                model.validateSource()
            }
            if !model.isLibrary {
                section("Results") {
                    choice("Hide titles with no chapters", symbol: "Funnel", selected: model.draft.hidesEmpty) {
                        model.draft.hidesEmpty.toggle()
                    }
                }
                section("Language") {
                    choice("All languages", symbol: "Globe", selected: model.draft.language == nil)
                    {
                        model.draft.language = nil
                        model.validateSource()
                    }
                    ForEach(model.languages, id: \.self) { language in
                        // Desktop marks the preferred source language with a star.
                        choice(
                            (Locale.current.localizedString(forLanguageCode: language) ?? language)
                                + (language == preferredLanguage ? " · Preferred" : ""),
                            symbol: "Translate", selected: model.draft.language == language
                        ) {
                            model.draft.language = language
                            model.validateSource()
                        }
                    }
                }
            }
            section("Sources") {
                choice("All sources", symbol: "Stack", selected: model.draft.sourceID == nil) {
                    model.draft.sourceID = nil
                }
                ForEach(model.visibleSources) { source in
                    choice(
                        source.name + (source.isPinned ? " ★" : ""),
                        symbol: "Plugs", selected: model.draft.sourceID == source.id
                    ) {
                        model.draft.sourceID = source.id
                    }
                    .contextMenu {
                        Button(source.isPinned ? "Unpin source" : "Pin source",
                               phosphor: source.isPinned ? "PushPinSlash" : "PushPin") {
                            SourcePins.toggle(source.id)
                            Task { await model.loadSources() }
                        }
                    }
                }
            }
            .firstLoadSkeleton(
                "search-sources-\(model.isLibrary)", loading: model.sourcesAreLoading, style: .chips
            )
            if model.sourcesAreLoading {
                ContentSkeleton(style: .chips)
            } else if let message = model.sourceMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("Reload sources") { Task { await model.loadSources() } }
            } else if model.visibleSources.isEmpty {
                Text("No sources match these filters.").font(.footnote).foregroundStyle(
                    .secondary)
            }
            if !model.isLibrary {
                TextField("Find a genre", text: $genreQuery)
                    .font(.subheadline)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                    .autocorrectionDisabled()
                    .accessibilityLabel("Find a genre")
                section("Genres") {
                    ForEach(matchingGenres, id: \.self) { genre in
                        choice(
                            genre, symbol: genreSymbol(genre),
                            selected: model.draft.genres.contains(genre)
                        ) {
                            if model.draft.genres.contains(genre) {
                                model.draft.genres.remove(genre)
                            } else {
                                model.draft.genres.insert(genre)
                            }
                        }
                    }
                }
                section("Match genres") {
                    ForEach(SearchOptions.Match.allCases) { match in
                        choice(
                            match.rawValue, symbol: match == .all ? "Intersect" : "Unite",
                            selected: model.draft.match == match
                        ) {
                            model.draft.match = match
                        }
                    }
                }
                section("Status") {
                    choice(
                        "Any status", symbol: "CirclesFour", selected: model.draft.statuses.isEmpty
                    ) {
                        model.draft.statuses = []
                    }
                    ForEach(SearchOptions.Status.allCases) { status in
                        choice(
                            status.rawValue, symbol: statusSymbol(status),
                            selected: model.draft.statuses.contains(status)
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
            if !model.canApply {
                Text("Choose a source for source search.").font(.footnote).foregroundStyle(
                    .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private func sortSymbol(_ sort: SearchOptions.Sort) -> String {
        switch sort {
        case .sourceOrder: "ListNumbers"
        case .titleAscending: "SortAscending"
        case .titleDescending: "SortDescending"
        }
    }

    private func methodSymbol(_ method: SearchOptions.Method) -> String {
        switch method {
        case .keyword: "MagnifyingGlass"
        case .tags: "Tag"
        case .source: "Plugs"
        }
    }

    private func statusSymbol(_ status: SearchOptions.Status) -> String {
        switch status {
        case .any: "CirclesFour"
        case .ongoing: "Play"
        case .completed: "CheckCircle"
        case .hiatus: "Pause"
        case .cancelled: "Prohibit"
        case .finished: "FlagCheckered"
        }
    }

    private func genreSymbol(_ genre: String) -> String {
        switch genre {
        case "Action": "Lightning"
        case "Adventure": "Compass"
        case "Comedy": "Smiley"
        case "Drama": "SmileySad"
        case "Fantasy": "CastleTurret"
        case "Romance": "Heart"
        case "Sci-Fi": "Planet"
        case "Slice of Life": "Coffee"
        case "Horror": "Skull"
        case "Mystery": "Detective"
        case "Thriller": "Heartbeat"
        case "Sports": "Basketball"
        case "Supernatural": "Ghost"
        case "Mecha": "Robot"
        case "Historical": "Scroll"
        case "Psychological": "Brain"
        case "School Life": "GraduationCap"
        case "Shounen", "Seinen", "Josei", "Shoujo": "Users"
        case "Isekai": "DoorOpen"
        case "Martial Arts": "HandFist"
        case "Magic": "MagicWand"
        case "Music": "MusicNotes"
        case "Cooking": "CookingPot"
        case "Medical": "FirstAidKit"
        case "Military": "Shield"
        case "Harem": "UsersThree"
        case "Ecchi": "Flame"
        default: "Tag"
        }
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: @escaping () -> Content
    )
        -> some View
    {
        SearchOptionSection(title: title, content: content)
    }

    private func choice(
        _ title: String, symbol: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        SearchOptionChoice(title: title, symbol: symbol, selected: selected, action: action)
    }
}

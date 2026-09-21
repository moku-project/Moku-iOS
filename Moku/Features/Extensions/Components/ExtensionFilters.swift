import SwiftUI

struct ExtensionFilters: View {
    @Bindable var model: ExtensionsViewModel
    let repositoriesOnly: Bool
    let title: String
    let close: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        PhosphorIcon("MagnifyingGlass").iconSize(20).foregroundStyle(.secondary)
                        TextField(
                            repositoriesOnly ? "Find repositories" : "Find extensions",
                            text: $model.query
                        )
                        .autocorrectionDisabled().textInputAutocapitalization(.never).submitLabel(
                            .search
                        )
                        .accessibilityIdentifier("extensions.query")
                        if !model.query.isEmpty {
                            Button {
                                model.query = ""
                            } label: {
                                PhosphorIcon("X").iconSize(18).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Clear search")
                        }
                    }.padding(.horizontal, 16).frame(minHeight: 52)
                        .modifier(FloatingSurface(cornerRadius: 26))
                    if !repositoriesOnly {
                        SearchOptionSection(title: "Repository") {
                            SearchOptionChoice(
                                title: "All repositories", symbol: "FolderSimple",
                                selected: model.repositoryID == nil
                            ) { model.repositoryID = nil }
                            ForEach(model.repositories) { repo in
                                SearchOptionChoice(
                                    title: repo.title, symbol: "FolderSimple",
                                    selected: model.repositoryID == repo.id
                                ) { model.repositoryID = repo.id }
                            }
                        }
                        SearchOptionSection(title: "Language") {
                            SearchOptionChoice(
                                title: "All languages", symbol: "Globe",
                                selected: model.language == nil
                            ) { model.language = nil }
                            ForEach(model.languages, id: \.self) { language in
                                SearchOptionChoice(
                                    title: Locale.current.localizedString(forLanguageCode: language)
                                        ?? language,
                                    symbol: "Globe", selected: model.language == language
                                ) { model.language = language }
                            }
                        }
                    }
                    Button("Reset search and filters") {
                        model.query = ""
                        model.repositoryID = nil
                        model.language = nil
                    }.frame(minHeight: 44).foregroundStyle(NavigationStyle.accent)
                }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }.background(NavigationStyle.background)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { close() } }
                }
        }.tint(NavigationStyle.accent).preferredColorScheme(.dark)

    }
}

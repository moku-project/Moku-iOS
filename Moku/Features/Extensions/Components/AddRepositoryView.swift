import SwiftUI

struct AddRepositoryView: View {
    @Bindable var model: ExtensionsViewModel
    @Binding var repositoryName: String
    @Binding var repositoryURL: String
    @Binding var isAdding: Bool
    @FocusState private var urlFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…/index.min.json", text: $repositoryURL)
                        .keyboardType(.URL).textContentType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($urlFocused)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .accessibilityLabel("Index URL")
                        .accessibilityIdentifier("extensions.repositoryURL")
                } header: {
                    Text("Index URL")
                } footer: {
                    Text(
                        "Paste a Mihon or Aniyomi repository link, or an LNReader plugins.min.json. Nothing installs until you choose an extension."
                    )
                }
                Section("Name") {
                    TextField("Optional", text: $repositoryName)
                        .submitLabel(.done)
                        .onSubmit(add)
                }
                if let error = model.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(
                            .orange)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle("Add Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isAdding = false }.disabled(model.isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isWorking {
                        ProgressView()
                    } else {
                        Button("Add", action: add)
                            .disabled(
                                repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(model.isWorking)
            .onAppear {
                model.error = nil
                urlFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        let url = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = repositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !model.isWorking else { return }
        Task {
            if await model.perform({ try await $0.add(url: url, name: name) }) {
                isAdding = false
                repositoryURL = ""
                repositoryName = ""
            }
        }
    }
}

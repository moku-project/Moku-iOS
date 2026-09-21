import SwiftUI

struct AddRepositoryView: View {
    @Bindable var model: ExtensionsViewModel
    @Binding var repositoryName: String
    @Binding var repositoryURL: String
    @Binding var isAdding: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (optional)", text: $repositoryName)
                TextField("HTTPS index URL", text: $repositoryURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("extensions.repositoryURL")
                Text("Nothing installs until you select an extension.").font(.footnote)
                    .foregroundStyle(.secondary)
                if let error = model.error { Text(error).foregroundStyle(.red) }
                if model.isWorking { ContentSkeleton(style: .settings, count: 1) }
            }
            .navigationTitle("Add repository").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isAdding = false }.disabled(model.isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let url = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = repositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            if await model.perform({ try await $0.add(url: url, name: name) }) {
                                isAdding = false
                                repositoryURL = ""
                                repositoryName = ""
                            }
                        }
                    }.disabled(repositoryURL.isEmpty || model.isWorking)
                }
            }
            .interactiveDismissDisabled(model.isWorking)
        }
    }

}

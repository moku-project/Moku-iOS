import SwiftUI

struct CreateFolderView: View {
    @Binding var folderName: String
    var folderNameFocused: FocusState<Bool>.Binding
    let creatingFolder: Bool
    let folderError: String?
    let createFolder: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.65))
                .ignoresSafeArea()
                .onTapGesture { if !creatingFolder { close() } }
            VStack(alignment: .leading, spacing: 24) {
                Text("New folder").font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity)
                TextField("Folder name", text: $folderName)
                    .focused(folderNameFocused)
                    .submitLabel(.done)
                    .onSubmit { createFolder() }
                    .disabled(creatingFolder)
                    .padding(14)
                    .background(
                        NavigationStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)
                    )
                    .accessibilityIdentifier("library.folderName")
                if let folderError {
                    Text(folderError).font(.footnote).foregroundStyle(.red)
                }
                HStack {
                    Button("Cancel") { close() }
                        .disabled(creatingFolder)
                    Spacer()
                    Button(creatingFolder ? "Creating…" : "Create") { createFolder() }
                        .disabled(
                            creatingFolder
                                || folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty
                        )
                        .accessibilityIdentifier("library.createFolder")
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .foregroundStyle(NavigationStyle.accent)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(NavigationStyle.background, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(NavigationStyle.accent.opacity(0.18), lineWidth: 0.5)
            }
            .padding(24)
        }
        .tint(NavigationStyle.accent)
        .preferredColorScheme(.dark)
        .onAppear { folderNameFocused.wrappedValue = true }
        .onDisappear { folderNameFocused.wrappedValue = false }

    }
}

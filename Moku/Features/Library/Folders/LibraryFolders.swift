import SwiftUI

/// Owns folder editing UI; LibraryView retains which overlays are presented.
struct LibraryFolders: ViewModifier {
    @Binding var foldersPresented: Bool
    @Binding var newFolderPresented: Bool
    let model: LibraryViewModel
    let selectSaved: () -> Void
    @Environment(LibraryStore.self) private var library
    @State private var draft = FolderViewModel()
    @State private var folderQuery = ""
    @FocusState private var folderNameFocused: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: foldersPresented || newFolderPresented ? 4 : 0)
            .allowsHitTesting(!foldersPresented && !newFolderPresented)
            .accessibilityHidden(foldersPresented || newFolderPresented)
            .overlay {
                if foldersPresented {
                    ZStack {
                        Color.black.opacity(0.55).ignoresSafeArea()
                            .onTapGesture { if !draft.isSaving { foldersPresented = false } }
                        GeometryReader { geometry in
                            FolderPicker(
                                visibleFolders: visibleFolders, selectedID: model.folder?.id,
                                folderQuery: $folderQuery, creatingFolder: draft.isSaving,
                                newFolderPresented: newFolderPresented,
                                select: { folder in
                                    selectSaved()
                                    model.folder = folder
                                    foldersPresented = false
                                }, close: { foldersPresented = false },
                                create: {
                                    draft.name = ""
                                    draft.error = nil
                                    newFolderPresented = true
                                    folderNameFocused = true
                                }
                            )
                            .frame(maxWidth: 480)
                            .frame(height: min(560, max(220, geometry.size.height - 48)))
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24)
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                            }
                            .padding(24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .blur(radius: newFolderPresented ? 4 : 0)
                    .allowsHitTesting(!newFolderPresented)
                    .accessibilityHidden(newFolderPresented)
                    .accessibilityAddTraits(.isModal)
                }
            }
            .overlay {
                if newFolderPresented {
                    CreateFolderView(
                        folderName: $draft.name, folderNameFocused: $folderNameFocused,
                        creatingFolder: draft.isSaving, folderError: draft.error,
                        createFolder: createFolder, close: { newFolderPresented = false }
                    )
                    .accessibilityAddTraits(.isModal)
                }
            }
            .onChange(of: foldersPresented) { _, presented in
                if !presented { folderQuery = "" }
            }
            .onChange(of: newFolderPresented) { _, presented in
                if !presented {
                    folderNameFocused = false
                    draft.name = ""
                    draft.error = nil
                }
            }
    }

    private func createFolder() {
        Task {
            guard let folder = await draft.create(in: library) else { return }
            selectSaved()
            model.folder = folder
            draft.name = ""
            newFolderPresented = false
            foldersPresented = false
        }
    }

    private var visibleFolders: [LibraryFolder] {
        let query = folderQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.organization.folders.filter {
            query.isEmpty || $0.name.localizedStandardContains(query)
        }
    }

}

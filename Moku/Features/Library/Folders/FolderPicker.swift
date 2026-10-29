import SwiftUI

struct FolderPicker: View {
    let visibleFolders: [LibraryFolder]
    let selectedID: UUID?
    @Binding var folderQuery: String
    let creatingFolder: Bool
    let newFolderPresented: Bool
    let select: (LibraryFolder) -> Void
    let close: () -> Void
    let create: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if visibleFolders.isEmpty {
                    Text(
                        folderQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "No folders" : "No matching folders"
                    )
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                ForEach(visibleFolders) { folder in
                    Button {
                        select(folder)
                    } label: {
                        HStack {
                            Label(folder.name, phosphor: "FolderSimple")
                            Spacer()
                        }
                    }.disabled(creatingFolder).foregroundStyle(
                        selectedID == folder.id ? NavigationStyle.accent : .primary
                    )
                    .listRowBackground(
                        selectedID == folder.id
                            ? NavigationStyle.accent.opacity(0.14) : .clear
                    )
                    .accessibilityAddTraits(selectedID == folder.id ? .isSelected : [])
                }
            }
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background)
            .tint(NavigationStyle.accent)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 12) {
                    HStack {
                        Button("Done") { close() }
                            .disabled(creatingFolder)
                            .frame(width: 60, height: 44, alignment: .leading)
                        Spacer()
                        Text("Folders").font(.headline).foregroundStyle(.primary)
                        Spacer()
                        Button {
                            create()
                        } label: {
                            PhosphorIcon("FolderSimplePlus").iconSize(24)
                                .frame(width: 44, height: 44)
                        }
                        .frame(width: 60, alignment: .trailing)
                        .disabled(creatingFolder || newFolderPresented)
                        .accessibilityLabel("New folder")
                        .accessibilityIdentifier("library.newFolder")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NavigationStyle.accent)
                    HStack(spacing: 10) {
                        PhosphorIcon("MagnifyingGlass").iconSize(18).foregroundStyle(.secondary)
                        TextField("Search folders", text: $folderQuery)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("library.searchFolders")
                        if !folderQuery.isEmpty {
                            Button {
                                folderQuery = ""
                            } label: {
                                PhosphorIcon("X").iconSize(16)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear folder search")
                        }
                    }
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(
                        NavigationStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                .background(NavigationStyle.background)
            }
        }
        .tint(NavigationStyle.accent)
        .themedColorScheme()

    }
}

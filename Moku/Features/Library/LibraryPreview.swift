import SwiftUI

#if DEBUG
    private struct LibraryPreviewHost: View {
        @State private var mode: ContentMode = .all
        @State private var library = ProfileLibrary(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "MokuPreviews/\(UUID().uuidString)"))

        var body: some View {
            NavigationStack {
                LibraryView(mode: $mode, onBrowse: {}, onSearch: {}, onOpen: { _ in })
                    .environment(library)
                    .background(NavigationStyle.background)
            }
            .defaultAppStorage(UserDefaults(suiteName: "Moku.Previews")!)
            .preferredColorScheme(.dark)
        }
    }

    #Preview("Library · controls and radial menu") {
        LibraryPreviewHost()
    }
#endif

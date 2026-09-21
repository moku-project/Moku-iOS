import SwiftUI

/// Resolves extension covers through the authenticated, cached backend proxy.
struct CoverImage: View {
    @AppStorage("preferences.cropCovers") private var cropCovers = true
    let url: URL?
    var symbol = "BookOpen"
    var isIcon = false
    var bareIcon = false
    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var loading = false

    var body: some View {
        ZStack {
            if !bareIcon { NavigationStyle.accent.opacity(0.12) }
            if loadedURL == url, let image {
                Image(uiImage: image).resizable().aspectRatio(
                    contentMode: isIcon || !cropCovers ? .fit : .fill
                )
                .padding(isIcon && !bareIcon ? 6 : 0)
            } else if loading {
                Rectangle().fill(.primary.opacity(0.08)).skeletonMotion("Cover is being prepared")
            } else {
                if bareIcon {
                    PhosphorIcon(symbol).iconSize(40).foregroundStyle(NavigationStyle.accent)
                } else {
                    PhosphorIcon(symbol).foregroundStyle(NavigationStyle.accent)
                }
            }
        }
        .firstLoadSkeleton(
            "cover-\(url?.absoluteString ?? "")", loading: loading, style: .cover,
            enabled: url != nil
        )
        .clipped()
        .accessibilityHidden(true)
        .onDisappear {
            // Lazy stacks preserve state: release off-screen pixels and let
            // the bounded shared cache decide which covers remain warm.
            image = nil
            loadedURL = nil
        }
        .task(id: url) {
            image = nil
            loadedURL = nil
            loading = url != nil
            guard let url else { return }
            do {
                image = try await CoverImagePipeline.shared.image(for: url)
                try Task.checkCancellation()
                loadedURL = url
                loading = false
            } catch {
                guard !Task.isCancelled else { return }
                loading = false
            }
        }
    }
}

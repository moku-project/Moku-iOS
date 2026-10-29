import SwiftUI

/// Resolves extension covers through the authenticated, cached backend proxy.
struct CoverImage: View {
    @AppStorage("preferences.cropCovers") private var cropCovers = true
    let url: URL?
    var contentMode: SwiftUI.ContentMode?
    var alignment: Alignment = .center
    var symbol = "BookOpen"
    var isIcon = false
    var bareIcon = false
    @State private var loaded: LoadedCover?
    @State private var loading = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: alignment) {
                if !bareIcon { NavigationStyle.accent.opacity(0.12) }
                if let image = resolvedImage {
                    Image(uiImage: image).resizable().aspectRatio(
                        contentMode: contentMode ?? (isIcon || !cropCovers ? .fit : .fill)
                    )
                    .padding(isIcon && !bareIcon ? 6 : 0)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment)
                } else if loading {
                    Rectangle().fill(.primary.opacity(0.08))
                } else {
                    if bareIcon {
                        PhosphorIcon(symbol).iconSize(40).foregroundStyle(NavigationStyle.accent)
                    } else {
                        PhosphorIcon(symbol).foregroundStyle(NavigationStyle.accent)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment)
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: url) {
            // A warm reappearance does not reset state, start a load, or flash
            // a placeholder. The weak handle leaves eviction to the shared cache.
            if let image = resolvedImage {
                if loaded?.url != url || loaded?.image == nil {
                    loaded = LoadedCover(url: url, image: image)
                }
                if loading { loading = false }
                return
            }
            loaded = nil
            loading = url != nil
            guard let url else { return }
            do {
                let prepared = try await CoverImagePipeline.shared.image(for: url)
                try Task.checkCancellation()
                loaded = LoadedCover(url: url, image: prepared)
                loading = false
            } catch {
                guard !Task.isCancelled else { return }
                loading = false
            }
        }
    }

    private var resolvedImage: UIImage? {
        if loaded?.url == url, let image = loaded?.image { return image }
        return CoverImagePipeline.cachedImage(for: url)
    }
}

/// Lazy containers retain view state after disappearance. Holding pixels weakly
/// avoids both unbounded image retention and per-cell teardown on every tab exit.
private final class LoadedCover {
    let url: URL?
    weak var image: UIImage?
    init(url: URL?, image: UIImage) {
        self.url = url
        self.image = image
    }
}

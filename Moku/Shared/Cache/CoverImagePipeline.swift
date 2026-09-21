import Foundation
import ImageIO
import UIKit

/// Full-resolution artwork is never decoded on the UI executor. Prepared
/// thumbnails are shared across Home, search, details and the library.
actor CoverImagePipeline {
    static let shared = CoverImagePipeline()
    private let images: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    private var pending: [URL: (UUID, Task<UIImage, Error>)] = [:]

    func image(for url: URL) async throws -> UIImage {
        guard let key = BackendAPI.coverURL(url.absoluteString) else {
            throw EmbeddedSearchError.message("Cover unavailable.")
        }
        try Task.checkCancellation()
        if let image = images.object(forKey: key as NSURL) { return image }
        if let (_, task) = pending[key] { return try await task.value }
        let id = UUID()
        let task = Task {
            let data = try await BackendAPI.shared.coverData(for: key)
            return try Self.thumbnail(data)
        }
        pending[key] = (id, task)
        do {
            let image = try await task.value
            if pending[key]?.0 == id {
                if let cg = image.cgImage {
                    images.setObject(image, forKey: key as NSURL, cost: cg.bytesPerRow * cg.height)
                }
                pending[key] = nil
            }
            try Task.checkCancellation()
            return image
        } catch {
            if pending[key]?.0 == id { pending[key] = nil }
            throw error
        }
    }

    static func thumbnail(_ data: Data) throws -> UIImage {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 600,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary)
        else {
            throw EmbeddedSearchError.message("Cover unavailable.")
        }
        return UIImage(cgImage: image)
    }

    /// Only warm the first screenful, with at most three requests per batch.
    /// Visible cells share this exact pipeline rather than fetching a second copy.
    func prefetch(_ urls: [URL]) async {
        var seen = Set<URL>()
        let unique = urls.filter { seen.insert($0).inserted }.prefix(12)
        await withTaskGroup(of: Void.self) { group in
            var iterator = unique.makeIterator()
            for _ in 0..<3 {
                if let url = iterator.next() {
                    group.addTask { _ = try? await self.image(for: url) }
                }
            }
            while await group.next() != nil {
                guard !Task.isCancelled, let url = iterator.next() else { continue }
                group.addTask { _ = try? await self.image(for: url) }
            }
        }
    }

    func clear() {
        pending.removeAll()
        images.removeAllObjects()
    }
}

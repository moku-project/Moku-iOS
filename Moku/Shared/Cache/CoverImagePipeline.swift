import Foundation
import ImageIO
import UIKit

/// Full-resolution artwork is never decoded on the UI executor. Prepared
/// thumbnails are shared across Home, search, details and the library.
actor CoverImagePipeline {
    static let shared = CoverImagePipeline()
    private nonisolated static let images = CoverMemoryCache()
    private struct Flight {
        let id: UUID
        let task: Task<UIImage, Error>
        var consumers: Set<UUID> = []
    }
    private var pending: [URL: Flight] = [:]

    nonisolated static func cachedImage(for url: URL?) -> UIImage? {
        guard let url, let key = BackendAPI.coverURL(url.absoluteString) else { return nil }
        return images.cache.object(forKey: key as NSURL)
    }

    func image(for url: URL) async throws -> UIImage {
        guard let key = BackendAPI.coverURL(url.absoluteString) else {
            throw EmbeddedSearchError.message("Cover unavailable.")
        }
        try Task.checkCancellation()
        if let image = Self.images.cache.object(forKey: key as NSURL) { return image }
        let consumer = UUID()
        var flight: Flight
        if let existing = pending[key] {
            flight = existing
        } else {
            flight = Flight(id: UUID(), task: Task {
                let data = try await BackendAPI.shared.coverData(for: key)
                try Task.checkCancellation()
                return try Self.thumbnail(data)
            })
        }
        flight.consumers.insert(consumer)
        pending[key] = flight
        let id = flight.id
        let task = flight.task
        do {
            let image = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                Task { await self.cancel(consumer, key: key, id: id) }
            }
            if pending[key]?.id == id {
                if let cg = image.cgImage {
                    Self.images.cache.setObject(image, forKey: key as NSURL, cost: cg.bytesPerRow * cg.height)
                }
                pending[key] = nil
            }
            try Task.checkCancellation()
            return image
        } catch {
            if pending[key]?.id == id { pending[key] = nil }
            throw error
        }
    }

    private func cancel(_ consumer: UUID, key: URL, id: UUID) {
        guard var flight = pending[key], flight.id == id else { return }
        flight.consumers.remove(consumer)
        if flight.consumers.isEmpty {
            pending[key] = nil
            flight.task.cancel()
        } else {
            pending[key] = flight
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

    func trimMemory() { Self.images.cache.removeAllObjects() }

    func clear() {
        pending.removeAll()
        Self.images.cache.removeAllObjects()
    }
}

/// NSCache supports concurrent lookup/eviction. Its decoded images are immutable.
/// A synchronous hit lets a revisited cell display its cover on its first frame.
private final class CoverMemoryCache: @unchecked Sendable {
    let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
}

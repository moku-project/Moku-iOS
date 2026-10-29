import CoreImage
import Foundation
import ImageIO
import UIKit

/// Bounds decoded pixels independently of source resolution, away from the main actor.
/// Stateless, so concurrent prefetches decode in parallel rather than queueing on one actor.
struct PageDecoder: Sendable {
    static let shared = PageDecoder()
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private var context: CIContext { Self.context }
    func decode(_ data: Data, contrast: Bool = false) async throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw EmbeddedSearchError.message("The source returned an unreadable image.")
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelSize(source),
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary)
        else {
            throw EmbeddedSearchError.message("The source returned an unreadable image.")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        let originalWidth =
            (properties?[
                orientation >= 5 ? kCGImagePropertyPixelHeight : kCGImagePropertyPixelWidth]
            as? NSNumber)?.doubleValue ?? Double(image.width)
        let scale = CGFloat(image.width) / max(1, originalWidth)
        if contrast {
            let filtered = CIImage(cgImage: image).applyingFilter(
                "CIColorControls", parameters: [kCIInputContrastKey: 1.15])
            if let result = context.createCGImage(filtered, from: filtered.extent) {
                return UIImage(cgImage: result, scale: scale, orientation: .up)
            }
        }
        return UIImage(cgImage: image, scale: scale, orientation: .up)
    }

    /// The thumbnail limit applies to the longest side. A fixed 2048 shrank tall
    /// webtoon strips to about 130 px wide, so bound the short side and the pixel
    /// count instead (about 32 MB decoded at most).
    private static func maxPixelSize(_ source: CGImageSource) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        guard width > 0, height > 0 else { return 2048 }
        let long = max(width, height), short = min(width, height)
        let shortTarget = min(short, 1600)
        let byShort = long * shortTarget / short
        let byPixels = long * sqrt(8_000_000 / (width * height))
        return Int(max(2048, min(long, byShort, byPixels)))
    }
}

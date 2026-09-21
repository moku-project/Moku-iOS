import CoreImage
import Foundation
import ImageIO
import UIKit

/// Bounds decoded pixels independently of source resolution, away from the main actor.
actor PageDecoder {
    static let shared = PageDecoder()
    private lazy var context = CIContext(options: [.cacheIntermediates: false])
    func decode(_ data: Data, contrast: Bool = false) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048,
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
}

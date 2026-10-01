import ArchiveCore
import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// Turns an original into an upright bitmap of one page, for OCR and for
/// display. Both use this, so a highlight box computed during OCR lands on
/// the same pixels it was found on.
enum PageImages {
    enum Failure: Error, LocalizedError {
        case unreadableImage, unreadablePDF, missingPage(Int), notAnImage

        var errorDescription: String? {
            switch self {
            case .unreadableImage: "The image couldn't be read."
            case .unreadablePDF: "The PDF couldn't be read."
            case .missingPage(let index): "The PDF has no page \(index + 1)."
            case .notAnImage: "A voice note has no page to show."
            }
        }
    }

    static func cgImage(of url: URL, type: AssetType, pageInAsset: Int, maxPixelSize: Int) throws -> CGImage {
        switch type {
        case .image:
            return try image(at: url, maxPixelSize: maxPixelSize)
        case .pdf:
            guard let document = CGPDFDocument(url as CFURL) else { throw Failure.unreadablePDF }
            // CGPDF pages are 1-based.
            guard let page = document.page(at: pageInAsset + 1) else { throw Failure.missingPage(pageInAsset) }
            guard let image = render(page, maxPixelSize: maxPixelSize) else { throw Failure.unreadablePDF }
            return image
        case .audio:
            throw Failure.notAnImage
        }
    }

    /// For SwiftUI, off the main actor.
    @concurrent
    static func load(_ url: URL, type: AssetType, pageInAsset: Int, maxPixelSize: Int) async -> UIImage? {
        guard let image = try? cgImage(of: url, type: type, pageInAsset: pageInAsset, maxPixelSize: maxPixelSize)
        else { return nil }
        return UIImage(cgImage: image)
    }

    /// Decodes at most `maxPixelSize` on the long edge, with the EXIF rotation
    /// applied: a 48MP photo is never held in memory at full size, and the
    /// result is upright, so OCR boxes need no further correction.
    private static func image(at url: URL, maxPixelSize: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Failure.unreadableImage }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.unreadableImage
        }
        return image
    }

    /// The crop box, as a viewer shows it, rotated upright, on white.
    private static func render(_ page: CGPDFPage, maxPixelSize: Int) -> CGImage? {
        let box = page.getBoxRect(.cropBox)
        let quarterTurned = page.rotationAngle % 180 != 0
        let size = quarterTurned ? CGSize(width: box.height, height: box.width) : box.size
        let scale = CGFloat(maxPixelSize) / max(size.width, size.height, 1)
        let width = Int(size.width * scale), height = Int(size.height * scale)

        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // getDrawingTransform handles rotation and the box's origin but never
        // scales up, so scale first and ask it to fit the page's own size.
        context.scaleBy(x: scale, y: scale)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size),
                                                     rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return context.makeImage()
    }
}

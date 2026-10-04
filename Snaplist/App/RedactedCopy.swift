import ArchiveCore
import Foundation
import UIKit

/// A copy of a record to send to someone: every page as an image, with the
/// lines that hold card and account numbers, addresses, phone numbers and
/// ID numbers blacked out. The original is never changed.
enum RedactedCopy {
    struct Result: Identifiable {
        let url: URL
        /// Lines hidden, across all pages.
        let hidden: Int
        /// Private lines whose place on the page isn't known, so weren't hidden.
        let missed: Int
        var id: URL { url }
    }

    @MainActor
    static func make(_ record: Record, archive: Archive) throws -> Result {
        let store = archive.store
        let assets = try store.assets(of: record.id).filter { $0.type == .image || $0.type == .pdf }
        let pages = try store.pages(of: record.id)
        var hidden = 0, missed = 0
        var drawn: [(image: CGImage, boxes: [CGRect])] = []

        for page in pages {
            guard let asset = assets.first(where: { $0.id == page.assetId }), let id = page.id else { continue }
            let image = try PageImages.cgImage(of: archive.url(for: asset), type: asset.type, pageInAsset: page.pageInAsset,
                                               maxPixelSize: 2400)
            let lines = try store.lines(of: id)
            let recognized = RecognizedPage(lines: lines.map { RecognizedLine(text: $0.text, box: $0.box) }, source: page.textSource)
            let size = CGSize(width: image.width, height: image.height)
            var boxes: [CGRect] = []
            for (index, _) in Redactor.privateLines(recognized) {
                guard let box = lines[index].box else { missed += 1; continue }
                // A little wider than the text, so no edge of a digit shows.
                boxes.append(CGRect(x: box.x * size.width, y: box.y * size.height,
                                    width: box.width * size.width, height: box.height * size.height).insetBy(dx: -6, dy: -4))
                hidden += 1
            }
            drawn.append((image, boxes))
        }

        let first = drawn.first.map { CGSize(width: $0.image.width, height: $0.image.height) } ?? CGSize(width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first)).pdfData { context in
            for (image, boxes) in drawn {
                let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                UIImage(cgImage: image).draw(in: bounds)
                UIColor.black.setFill()
                for box in boxes { UIBezierPath(roundedRect: box, cornerRadius: 3).fill() }
            }
        }
        let name = record.title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name) (private details hidden).pdf")
        try data.write(to: url, options: .atomic)
        return Result(url: url, hidden: hidden, missed: missed)
    }
}

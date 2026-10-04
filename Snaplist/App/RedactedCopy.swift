import ArchiveCore
import Foundation
import UIKit

/// A copy of a record to send to someone: every page as an image, with the
/// lines that hold card and account numbers, addresses, phone numbers, names
/// and ID numbers blacked out. Lines can be hidden or shown by hand before
/// it's sent. The original is never changed.
enum RedactedCopy {
    /// The person's own words to always hide: their name, street, phone.
    static let wordsKey = "alwaysHideWords"

    static var words: [String] {
        (UserDefaults.standard.string(forKey: wordsKey) ?? "")
            .split(whereSeparator: { $0 == "," || $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    struct Line: Identifiable {
        let id: Int
        let text: String
        /// Top-left origin, as a fraction of the page.
        let rect: CGRect
        var hidden: Bool
    }

    struct Page: Identifiable {
        let id: Int
        let image: CGImage
        var lines: [Line]
    }

    struct Draft: Identifiable {
        let title: String
        var pages: [Page]
        /// Private lines with no place on the page, so not hidden.
        let missed: Int
        var id: String { title }
        var hiddenCount: Int { pages.reduce(0) { $0 + $1.lines.count(where: \.hidden) } }
    }

    @MainActor
    static func draft(_ record: Record, archive: Archive) throws -> Draft {
        let store = archive.store
        let assets = try store.assets(of: record.id).filter { $0.type == .image || $0.type == .pdf }
        let words = words
        var pages: [Page] = []
        var missed = 0

        for page in try store.pages(of: record.id) {
            guard let asset = assets.first(where: { $0.id == page.assetId }), let pageId = page.id else { continue }
            let image = try PageImages.cgImage(of: archive.url(for: asset), type: asset.type, pageInAsset: page.pageInAsset,
                                               maxPixelSize: 2400)
            let stored = try store.lines(of: pageId)
            let recognized = RecognizedPage(lines: stored.map { RecognizedLine(text: $0.text, box: $0.box) }, source: page.textSource)
            let hidden = Set(Redactor.privateLines(recognized, alsoHide: words).map(\.index))
            missed += hidden.count { stored[$0].box == nil }
            let lines = stored.enumerated().compactMap { index, line -> Line? in
                guard let box = line.box else { return nil }
                return Line(id: index, text: line.text, rect: CGRect(x: box.x, y: box.y, width: box.width, height: box.height),
                            hidden: hidden.contains(index))
            }
            pages.append(Page(id: pages.count, image: image, lines: lines))
        }
        return Draft(title: record.title, pages: pages, missed: missed)
    }

    /// The PDF to send, with the hidden lines blacked out.
    static func render(_ draft: Draft) throws -> URL {
        let first = draft.pages.first.map { CGSize(width: $0.image.width, height: $0.image.height) } ?? CGSize(width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first)).pdfData { context in
            for page in draft.pages {
                let size = CGSize(width: page.image.width, height: page.image.height)
                context.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                UIImage(cgImage: page.image).draw(in: CGRect(origin: .zero, size: size))
                UIColor.black.setFill()
                for line in page.lines where line.hidden {
                    // A little wider than the text, so no edge of a letter shows.
                    let box = CGRect(x: line.rect.minX * size.width, y: line.rect.minY * size.height,
                                     width: line.rect.width * size.width, height: line.rect.height * size.height)
                    UIBezierPath(roundedRect: box.insetBy(dx: -6, dy: -4), cornerRadius: 3).fill()
                }
            }
        }
        let name = draft.title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name) (private details hidden).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}

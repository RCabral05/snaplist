import ArchiveCore
import Foundation
import PDFKit
import Vision

/// Reads text with Apple's on-device frameworks; nothing leaves the phone.
///
/// - Images: Vision OCR, line by line, with each line's position kept.
/// - PDFs: a page's own text layer when it has one, since that is exact;
///   otherwise (a scan saved as PDF) the page is rendered and OCR'd.
///
/// OCR makes mistakes, especially on faded thermal receipts. The source of
/// every page is recorded so the UI can say which text was read by a machine.
struct VisionTextExtractor: TextExtractor {
    /// Long edge for OCR: enough for receipt fine print.
    static let ocrPixelSize = 3000
    /// A PDF page with fewer non-space characters than this is treated as a scan.
    static let minimumTextLayer = 20

    @concurrent
    func pages(of fileURL: URL, type: AssetType) async throws -> [RecognizedPage] {
        switch type {
        case .image:
            let image = try PageImages.cgImage(of: fileURL, type: .image, pageInAsset: 0, maxPixelSize: Self.ocrPixelSize)
            return [try await recognize(image)]
        case .pdf:
            return try await pdfPages(fileURL)
        }
    }

    private func pdfPages(_ url: URL) async throws -> [RecognizedPage] {
        guard let document = PDFDocument(url: url) else { throw PageImages.Failure.unreadablePDF }
        guard !document.isLocked else { throw ExtractionFailure.passwordProtected }

        var pages: [RecognizedPage] = []
        for index in 0..<document.pageCount {
            let text = document.page(at: index)?.string ?? ""
            if text.count(where: { !$0.isWhitespace }) >= Self.minimumTextLayer {
                let lines = text
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .map { RecognizedLine(text: $0) }
                pages.append(RecognizedPage(lines: lines, source: .pdfText))
            } else {
                let image = try PageImages.cgImage(of: url, type: .pdf, pageInAsset: index,
                                                   maxPixelSize: Self.ocrPixelSize)
                pages.append(try await recognize(image))
            }
        }
        return pages
    }

    private func recognize(_ image: CGImage) async throws -> RecognizedPage {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let observations = try await request.perform(on: image, orientation: .up)
        let lines = observations
            .compactMap { observation -> RecognizedLine? in
                guard let best = observation.topCandidates(1).first else { return nil }
                // Vision's origin is bottom-left; ours is top-left.
                let box = observation.boundingBox
                return RecognizedLine(
                    text: best.string,
                    box: PageRect(x: box.origin.x, y: 1 - box.origin.y - box.height,
                                  width: box.width, height: box.height),
                    confidence: Double(best.confidence))
            }
            // Top to bottom, then left to right, so stored text reads in order.
            .sorted { a, b in
                guard let ab = a.box, let bb = b.box else { return false }
                return abs(ab.y - bb.y) > ab.height / 2 ? ab.y < bb.y : ab.x < bb.x
            }
        return RecognizedPage(lines: lines, source: .ocr)
    }
}

enum ExtractionFailure: Error, LocalizedError {
    case passwordProtected

    var errorDescription: String? {
        "This PDF is password protected. Remove the password and import it again."
    }
}

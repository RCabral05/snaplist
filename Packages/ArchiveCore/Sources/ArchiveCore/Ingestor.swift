import Foundation

/// Reads the text out of one original. The app supplies the real one (Vision for
/// images, PDFKit for PDFs, falling back to OCR for scanned pages); tests supply
/// a fake. Throwing marks the record failed with the error as its reason.
public protocol TextExtractor: Sendable {
    func pages(of fileURL: URL, type: AssetType) async throws -> [RecognizedPage]

    /// The pages read as images, ignoring any text layer: for PDFs whose
    /// text layer comes out in an order that can't be read as rows. Nil if
    /// this extractor can't.
    func recognizedPages(of fileURL: URL, type: AssetType) async throws -> [RecognizedPage]?
}

extension TextExtractor {
    public func recognizedPages(of fileURL: URL, type: AssetType) async throws -> [RecognizedPage]? { nil }
}

/// Turns pending records into searchable ones.
public struct Ingestor: Sendable {
    public let archive: Archive
    public let extractor: any TextExtractor

    public init(archive: Archive, extractor: any TextExtractor) {
        self.archive = archive
        self.extractor = extractor
    }

    /// Extracts every original of the record and saves the text, or records
    /// why it could not. Never throws: a failure belongs on the record, where
    /// the person can see it and retry.
    public func process(_ recordId: UUID) async {
        do {
            var extracted: [ExtractedAsset] = []
            for asset in try archive.store.assets(of: recordId) {
                let pages = try await extractor.pages(of: archive.url(for: asset), type: asset.type)
                extracted.append(ExtractedAsset(assetId: asset.id, pages: pages))
            }
            try archive.store.saveText(extracted, for: recordId)

            // A statement whose text layer gave no transactions: read the
            // pages as images instead, which always gives each line a place.
            if try archive.store.needsImageReading(recordId) {
                var reread: [ExtractedAsset] = []
                for (asset, original) in zip(try archive.store.assets(of: recordId), extracted) {
                    if asset.type == .pdf,
                       let pages = try await extractor.recognizedPages(of: archive.url(for: asset), type: asset.type) {
                        reread.append(ExtractedAsset(assetId: asset.id, pages: pages))
                    } else {
                        reread.append(original)
                    }
                }
                try archive.store.saveText(reread, for: recordId)
            }
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            try? archive.store.markFailed(recordId, reason: reason)
        }
    }

    /// Oldest first. Covers imports interrupted by the app being closed, since
    /// a record stays `pending` until its text is saved.
    public func processPending() async {
        for id in (try? archive.store.pendingRecordIds()) ?? [] {
            await process(id)
        }
    }
}

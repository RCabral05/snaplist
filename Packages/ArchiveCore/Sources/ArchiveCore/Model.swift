import Foundation
import GRDB

/// What a record is. Drives filters now and, later, which extractor runs on it.
public enum RecordKind: String, Codable, CaseIterable, Sendable {
    case receipt, statement, bill, warranty, manual, document, item, other
}

/// Where a record is in the import pipeline. A record is listed and openable from
/// the moment its originals are saved; only search has to wait for `ready`.
public enum IngestStatus: String, Codable, Sendable {
    case pending, ready, failed
}

public enum AssetType: String, Codable, Sendable {
    case image, pdf
}

/// Where a page's text came from. A PDF's own text layer is exact; OCR is not,
/// and the UI should never present the two as equally trustworthy.
public enum TextSource: String, Codable, Sendable {
    case pdfText, ocr
}

/// Who named a record, which decides whether the app may rename it.
public enum NameSource: String, Codable, Sendable {
    /// A placeholder ("Scan Sep 30…"): replaced by a name read from the text.
    case automatic
    /// The imported file's name: kept, though the category may still be guessed.
    case file
    /// Typed or chosen by the person: never changed by the app.
    case person
}

/// One thing the person saved: a receipt, a statement, a photo of a shelf.
public struct Record: Codable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public var id: UUID
    public var kind: RecordKind
    public var title: String
    public var createdAt: Date
    public var status: IngestStatus
    public var failureReason: String?
    public var nameSource: NameSource
    /// The date the record is about: a receipt's purchase date, a statement's
    /// closing date. Nil until read, or if none was found.
    public var documentDate: Day?
    /// Set by hand, so re-reading the text leaves it alone.
    public var documentDateEdited: Bool

    /// What to sort and group by: the document's own date if known, else
    /// the day it was added.
    public var effectiveDay: Day { documentDate ?? Day(createdAt) }

    public init(id: UUID = UUID(), kind: RecordKind, title: String, createdAt: Date,
                status: IngestStatus = .pending, failureReason: String? = nil,
                nameSource: NameSource = .person, documentDate: Day? = nil, documentDateEdited: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.status = status
        self.failureReason = failureReason
        self.nameSource = nameSource
        self.documentDate = documentDate
        self.documentDateEdited = documentDateEdited
    }
}

/// An original file, kept byte-for-byte as imported. Everything else about a
/// record is derived from these and can be rebuilt from them.
public struct Asset: Codable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public var id: UUID
    public var recordId: UUID
    public var position: Int
    public var type: AssetType
    /// Relative to `ArchiveFiles.root`.
    public var fileName: String
    public var byteSize: Int64
}

/// One page of text. A photo is one page; a PDF is one per PDF page. `id` is the
/// rowid of the page's row in the search index, which is how a hit finds its way
/// back to the page it came from.
public struct Page: Codable, Hashable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var recordId: UUID
    public var assetId: UUID
    /// 0-based across the whole record.
    public var position: Int
    /// 0-based within the asset; the PDF page to open.
    public var pageInAsset: Int
    public var text: String
    public var textSource: TextSource

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// A line of text and where it sits on the page, so a search hit or an extracted
/// value can be shown highlighted on the original rather than just asserted.
public struct TextLine: Codable, Hashable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var pageId: Int64
    public var position: Int
    public var text: String
    public var x: Double?
    public var y: Double?
    public var width: Double?
    public var height: Double?
    public var confidence: Double?

    public var box: PageRect? {
        guard let x, let y, let width, let height else { return nil }
        return PageRect(x: x, y: y, width: width, height: height)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// A rectangle in 0...1 page coordinates, origin top-left. Vision reports
/// bottom-left; the adapter that calls it converts, so nothing past it has to care.
public struct PageRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// What a text extractor hands back for one page, before it is stored.
public struct RecognizedPage: Sendable {
    public var lines: [RecognizedLine]
    public var source: TextSource

    public init(lines: [RecognizedLine], source: TextSource) {
        self.lines = lines
        self.source = source
    }

    public var text: String { lines.map(\.text).joined(separator: "\n") }
}

public struct RecognizedLine: Sendable {
    public var text: String
    /// Nil when the source has no geometry, e.g. a PDF text layer read as a string.
    public var box: PageRect?
    public var confidence: Double?

    public init(text: String, box: PageRect? = nil, confidence: Double? = nil) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

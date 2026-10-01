import Foundation
import GRDB

/// The database: records, their originals' metadata, page text, and the search
/// index. Every write goes through here, which is what keeps the index in step
/// with the pages - there are no triggers to keep in mind.
public struct ArchiveStore: Sendable {
    let db: any DatabaseWriter

    public static func open(at url: URL) throws -> ArchiveStore {
        try ArchiveStore(db: DatabasePool(path: url.path))
    }

    public static func inMemory() throws -> ArchiveStore {
        try ArchiveStore(db: DatabaseQueue())
    }

    init(db: any DatabaseWriter) throws {
        self.db = db
        try Self.migrator.migrate(db)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE record (
                    id BLOB PRIMARY KEY NOT NULL,
                    kind TEXT NOT NULL,
                    title TEXT NOT NULL,
                    createdAt DATETIME NOT NULL,
                    status TEXT NOT NULL,
                    failureReason TEXT
                );
                CREATE INDEX record_createdAt ON record(createdAt);

                CREATE TABLE asset (
                    id BLOB PRIMARY KEY NOT NULL,
                    recordId BLOB NOT NULL REFERENCES record(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    type TEXT NOT NULL,
                    fileName TEXT NOT NULL,
                    byteSize INTEGER NOT NULL
                );
                CREATE INDEX asset_recordId ON asset(recordId);

                CREATE TABLE page (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    recordId BLOB NOT NULL REFERENCES record(id) ON DELETE CASCADE,
                    assetId BLOB NOT NULL REFERENCES asset(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    pageInAsset INTEGER NOT NULL,
                    text TEXT NOT NULL,
                    textSource TEXT NOT NULL
                );
                CREATE INDEX page_recordId ON page(recordId);

                CREATE TABLE textLine (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    pageId INTEGER NOT NULL REFERENCES page(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    text TEXT NOT NULL,
                    x REAL, y REAL, width REAL, height REAL,
                    confidence REAL
                );
                CREATE INDEX textLine_pageId ON textLine(pageId);

                -- One row per page, rowid = page.id. The title is repeated on each
                -- of a record's pages so a title match ranks like a text match.
                CREATE VIRTUAL TABLE searchIndex USING fts5(
                    title, body, tokenize = 'unicode61 remove_diacritics 2'
                );
                """)
        }
        migrator.registerMigration("v2-nameSource") { db in
            try db.execute(sql: """
                ALTER TABLE record ADD COLUMN nameSource TEXT NOT NULL DEFAULT 'person';
                -- Records made before this existed: the placeholders are recognisable.
                UPDATE record SET nameSource = 'automatic' WHERE title LIKE 'Scan %' OR title LIKE 'Photo %';
                """)
        }
        migrator.registerMigration("v3-transactions") { db in
            try db.execute(sql: """
                ALTER TABLE record ADD COLUMN documentDate TEXT;
                ALTER TABLE record ADD COLUMN documentDateEdited BOOLEAN NOT NULL DEFAULT 0;

                -- Amounts read from records. Positions, not page ids: pages are
                -- replaced when text is read again, positions stay the same.
                CREATE TABLE txn (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    recordId BLOB NOT NULL REFERENCES record(id) ON DELETE CASCADE,
                    pagePosition INTEGER,
                    linePosition INTEGER,
                    date TEXT,
                    merchant TEXT NOT NULL,
                    memo TEXT NOT NULL,
                    amountCents INTEGER NOT NULL CHECK (amountCents >= 0),
                    currency TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    category TEXT NOT NULL,
                    source TEXT NOT NULL,
                    isEdited BOOLEAN NOT NULL DEFAULT 0
                );
                CREATE INDEX txn_recordId ON txn(recordId);
                CREATE INDEX txn_date ON txn(date);
                """)
        }
        return migrator
    }

    // MARK: Reading

    public func record(_ id: UUID) throws -> Record? {
        try db.read { try Record.fetchOne($0, key: id) }
    }

    /// Newest first.
    public func records(kind: RecordKind? = nil) throws -> [Record] {
        try db.read { try Self.recordsRequest(kind: kind).fetchAll($0) }
    }

    /// The record list now and again after every change, newest first. Lets the
    /// app follow the archive without importing GRDB.
    public func recordUpdates(kind: RecordKind? = nil) -> some AsyncSequence<[Record], any Error> {
        ValueObservation
            .tracking { try Self.recordsRequest(kind: kind).fetchAll($0) }
            // A pool can deliver the same list twice, e.g. the initial value
            // again right after observation starts.
            .removeDuplicates()
            .values(in: db)
    }

    public func assets(of recordId: UUID) throws -> [Asset] {
        try db.read {
            try Asset.filter(Column("recordId") == recordId).order(Column("position")).fetchAll($0)
        }
    }

    public func pages(of recordId: UUID) throws -> [Page] {
        try db.read {
            try Page.filter(Column("recordId") == recordId).order(Column("position")).fetchAll($0)
        }
    }

    public func lines(of pageId: Int64) throws -> [TextLine] {
        try db.read {
            try TextLine.filter(Column("pageId") == pageId).order(Column("position")).fetchAll($0)
        }
    }

    public func pendingRecordIds() throws -> [UUID] {
        try db.read {
            try UUID.fetchAll($0, sql: "SELECT id FROM record WHERE status = ? ORDER BY createdAt",
                              arguments: [IngestStatus.pending.rawValue])
        }
    }

    /// By the date each record is about, so an August receipt scanned in
    /// October sits with August.
    private static func recordsRequest(kind: RecordKind?) -> QueryInterfaceRequest<Record> {
        var request = Record.order(sql: "COALESCE(documentDate, substr(createdAt, 1, 10)) DESC, createdAt DESC")
        if let kind { request = request.filter(Column("kind") == kind.rawValue) }
        return request
    }

    // MARK: Writing

    public func insert(_ record: Record, assets: [Asset]) throws {
        try db.write { db in
            try record.insert(db)
            for asset in assets { try asset.insert(db) }
        }
    }

    /// Kind and title are the parts a person edits; status belongs to the
    /// pipeline. Either edit makes the record theirs: no more automatic naming.
    /// Refiling a record reads its amounts again for the new kind: a
    /// "document" refiled as a receipt gets its total.
    public func update(_ record: Record) throws {
        var record = record
        record.nameSource = .person
        try db.write { db in
            let previousKind = try Record.fetchOne(db, key: record.id)?.kind
            try record.update(db, columns: ["kind", "title", "nameSource"])
            try db.execute(
                sql: "UPDATE searchIndex SET title = ? WHERE rowid IN (SELECT id FROM page WHERE recordId = ?)",
                arguments: [record.title, record.id])
            if previousKind != record.kind, record.status == .ready {
                try Self.applyExtraction(to: &record, pages: try Self.storedPages(of: record.id, in: db), in: db)
                try record.update(db, columns: ["documentDate"])
            }
        }
    }

    /// Replaces a record's pages, lines and index rows with freshly extracted
    /// ones and marks it ready, in one transaction: a search never sees half a
    /// record. Safe to run twice; the second run just replaces the first.
    /// Does nothing if the record was deleted while its text was being read.
    public func saveText(_ extracted: [ExtractedAsset], for recordId: UUID) throws {
        try db.write { db in
            guard var record = try Record.fetchOne(db, key: recordId) else { return }
            try Self.removeText(of: recordId, in: db)
            // Before the index rows are written, so they carry the new name.
            Self.applySuggestion(Suggester.suggest(extracted.flatMap(\.pages)), to: &record)

            var position = 0
            for asset in extracted {
                for (pageInAsset, recognized) in asset.pages.enumerated() {
                    var page = Page(id: nil, recordId: recordId, assetId: asset.assetId,
                                    position: position, pageInAsset: pageInAsset,
                                    text: recognized.text, textSource: recognized.source)
                    try page.insert(db)
                    position += 1
                    guard let pageId = page.id else { continue }

                    for (index, line) in recognized.lines.enumerated() {
                        var row = TextLine(id: nil, pageId: pageId, position: index, text: line.text,
                                           x: line.box?.x, y: line.box?.y,
                                           width: line.box?.width, height: line.box?.height,
                                           confidence: line.confidence)
                        try row.insert(db)
                    }
                    try db.execute(sql: "INSERT INTO searchIndex(rowid, title, body) VALUES (?, ?, ?)",
                                   arguments: [pageId, record.title, page.text])
                }
            }

            try Self.applyExtraction(to: &record, pages: extracted.flatMap(\.pages), in: db)
            record.status = .ready
            record.failureReason = nil
            try record.update(db)
        }
    }

    public func markFailed(_ recordId: UUID, reason: String) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE record SET status = ?, failureReason = ? WHERE id = ?",
                           arguments: [IngestStatus.failed.rawValue, reason, recordId])
        }
    }

    /// Puts a failed record back in the queue.
    public func markPending(_ recordId: UUID) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE record SET status = ?, failureReason = NULL WHERE id = ?",
                           arguments: [IngestStatus.pending.rawValue, recordId])
        }
    }

    public func delete(_ recordId: UUID) throws {
        try db.write { db in
            try Self.removeText(of: recordId, in: db)
            _ = try Record.deleteOne(db, key: recordId)
        }
    }

    public func deleteAll() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM searchIndex")
            _ = try Record.deleteAll(db)
        }
    }

    /// Re-reads stored text for what was added since a record was read:
    /// names for placeholder-named records, and dates and amounts for records
    /// that have none yet. Cheap enough to run at every launch. Returns how
    /// many records changed.
    @discardableResult
    public func refreshSuggestions() throws -> Int {
        try db.write { db in
            let records = try Record.fetchAll(db, sql: """
                SELECT * FROM record WHERE status = ? AND (
                    nameSource != ?
                    OR (documentDate IS NULL AND NOT documentDateEdited)
                    OR NOT EXISTS (SELECT 1 FROM txn WHERE txn.recordId = record.id))
                """, arguments: [IngestStatus.ready.rawValue, NameSource.person.rawValue])
            var changed = 0
            for var record in records {
                let recognized = try Self.storedPages(of: record.id, in: db)
                let before = record
                let transactionsBefore = try Amount.filter(Column("recordId") == record.id).fetchCount(db)
                Self.applySuggestion(Suggester.suggest(recognized), to: &record)
                try Self.applyExtraction(to: &record, pages: recognized, in: db)
                let transactionsAfter = try Amount.filter(Column("recordId") == record.id).fetchCount(db)
                guard record != before || transactionsBefore != transactionsAfter else { continue }
                try record.update(db, columns: ["kind", "title", "documentDate"])
                try db.execute(
                    sql: "UPDATE searchIndex SET title = ? WHERE rowid IN (SELECT id FROM page WHERE recordId = ?)",
                    arguments: [record.title, record.id])
                changed += 1
            }
            return changed
        }
    }

    /// A placeholder name is replaced; a file's name is kept. The category is
    /// only filled in while it's still the default.
    static func applySuggestion(_ suggestion: Suggestion, to record: inout Record) {
        guard record.nameSource != .person else { return }
        if record.nameSource == .automatic, let title = suggestion.title {
            record.title = title
        }
        if record.kind == .document, let kind = suggestion.kind {
            record.kind = kind
        }
    }

    /// Dates and amounts from the text, for the record's current kind.
    /// Amounts a person corrected are left exactly as they are.
    static func applyExtraction(to record: inout Record, pages: [RecognizedPage], in db: Database) throws {
        let merchant = Suggester.name(in: pages) ?? record.title
        let facts = Extractor.extract(kind: record.kind, pages: pages, recordId: record.id, merchant: merchant)
        if !record.documentDateEdited {
            record.documentDate = facts.documentDate
        }
        let hasEdits = try Bool.fetchOne(
            db, sql: "SELECT EXISTS (SELECT 1 FROM txn WHERE recordId = ? AND isEdited)", arguments: [record.id]) ?? false
        guard !hasEdits else { return }
        try db.execute(sql: "DELETE FROM txn WHERE recordId = ?", arguments: [record.id])
        for var transaction in facts.transactions {
            try transaction.insert(db)
        }
    }

    /// A record's text as it was recognised, rebuilt from the stored rows.
    static func storedPages(of recordId: UUID, in db: Database) throws -> [RecognizedPage] {
        try Page.filter(Column("recordId") == recordId).order(Column("position")).fetchAll(db).map { page in
            let lines = try TextLine.filter(Column("pageId") == page.id).order(Column("position")).fetchAll(db)
            return RecognizedPage(
                lines: lines.map { RecognizedLine(text: $0.text, box: $0.box, confidence: $0.confidence) },
                source: page.textSource)
        }
    }

    /// The index is a virtual table, so foreign keys cannot cascade into it.
    private static func removeText(of recordId: UUID, in db: Database) throws {
        try db.execute(sql: "DELETE FROM searchIndex WHERE rowid IN (SELECT id FROM page WHERE recordId = ?)",
                       arguments: [recordId])
        try db.execute(sql: "DELETE FROM page WHERE recordId = ?", arguments: [recordId])
    }
}

/// The text read from one original, in page order.
public struct ExtractedAsset: Sendable {
    public var assetId: UUID
    public var pages: [RecognizedPage]

    public init(assetId: UUID, pages: [RecognizedPage]) {
        self.assetId = assetId
        self.pages = pages
    }
}

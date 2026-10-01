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

    private static func recordsRequest(kind: RecordKind?) -> QueryInterfaceRequest<Record> {
        var request = Record.order(Column("createdAt").desc)
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

    /// Kind and title are the parts a person edits; status belongs to the pipeline.
    public func update(_ record: Record) throws {
        try db.write { db in
            try record.update(db, columns: ["kind", "title"])
            try db.execute(
                sql: "UPDATE searchIndex SET title = ? WHERE rowid IN (SELECT id FROM page WHERE recordId = ?)",
                arguments: [record.title, record.id])
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

import Foundation
import GRDB

public enum TagKind: String, Codable, CaseIterable, Sendable {
    /// Who a record is for or about: "Mom", "Work".
    case person
    /// Where it's from: "Boston", "Lake house".
    case place
}

/// A person or place a record can be tagged with. Names are unique per kind,
/// ignoring case.
public struct Tag: Codable, Hashable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var kind: TagKind
    public var name: String

    public init(id: Int64? = nil, kind: TagKind, name: String) {
        self.id = id
        self.kind = kind
        self.name = name
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Records found by the people and places a question names: "Mom's
/// warranties", "receipts from the Boston trip".
public struct TaggedRecords: Sendable {
    public var tags: [Tag]
    public var kind: RecordKind?
    /// Newest first.
    public var records: [Record]
}

extension ArchiveStore {
    // MARK: Reading

    /// Every tag, people first, by name.
    public func tags() throws -> [Tag] {
        try db.read {
            try Tag.order(Column("kind").desc, Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll($0)
        }
    }

    public func tags(of recordId: UUID) throws -> [Tag] {
        try db.read { try Self.tags(of: recordId, in: $0) }
    }

    /// Every record's tags at once, for the list.
    public func tagsByRecord() throws -> [UUID: [Tag]] {
        try db.read { db in
            var result: [UUID: [Tag]] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT recordTag.recordId, tag.* FROM recordTag JOIN tag ON tag.id = recordTag.tagId
                ORDER BY tag.kind DESC, tag.name COLLATE NOCASE
                """) {
                result[row["recordId"], default: []].append(try Tag(row: row))
            }
            return result
        }
    }

    static func tags(of recordId: UUID, in db: Database) throws -> [Tag] {
        try Tag.fetchAll(db, sql: """
            SELECT tag.* FROM tag JOIN recordTag ON recordTag.tagId = tag.id
            WHERE recordTag.recordId = ? ORDER BY tag.kind DESC, tag.name COLLATE NOCASE
            """, arguments: [recordId])
    }

    // MARK: Writing

    /// Tags a record with a person or place, creating the tag if it's new.
    @discardableResult
    public func addTag(_ name: String, kind: TagKind, to recordId: UUID) throws -> Tag {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!name.isEmpty, "a tag needs a name")
        return try db.write { db in
            var tag = try Tag.fetchOne(db, sql: "SELECT * FROM tag WHERE kind = ? AND name = ? COLLATE NOCASE",
                                       arguments: [kind.rawValue, name])
            if tag == nil {
                var new = Tag(kind: kind, name: name)
                try new.insert(db)
                tag = new
            }
            guard let tag, let tagId = tag.id else { throw DatabaseError(message: "tag was not saved") }
            try db.execute(sql: "INSERT OR IGNORE INTO recordTag (recordId, tagId) VALUES (?, ?)",
                           arguments: [recordId, tagId])
            try Self.reindexTitle(of: recordId, in: db)
            return tag
        }
    }

    /// Untags a record. A tag no record uses any more is removed.
    public func removeTag(_ tagId: Int64, from recordId: UUID) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM recordTag WHERE recordId = ? AND tagId = ?", arguments: [recordId, tagId])
            try db.execute(sql: "DELETE FROM tag WHERE id = ? AND NOT EXISTS (SELECT 1 FROM recordTag WHERE tagId = ?)",
                           arguments: [tagId, tagId])
            try Self.reindexTitle(of: recordId, in: db)
        }
    }

    // MARK: Search

    /// What the index holds as a record's title: its name and its tags, so
    /// searching "Boston" finds what's tagged Boston.
    static func indexTitle(of record: Record, in db: Database) throws -> String {
        ([record.title] + (try tags(of: record.id, in: db)).map(\.name)).joined(separator: " ")
    }

    static func reindexTitle(of recordId: UUID, in db: Database) throws {
        guard let record = try Record.fetchOne(db, key: recordId) else { return }
        try db.execute(
            sql: "UPDATE searchIndex SET title = ? WHERE rowid IN (SELECT id FROM page WHERE recordId = ?)",
            arguments: [try indexTitle(of: record, in: db), recordId])
    }

    // MARK: Questions

    /// When a question names saved people or places, the records tagged with
    /// all of them, narrowed to a category if one is named ("warranties").
    /// Nil when it names none.
    public func taggedRecords(matching question: String) throws -> TaggedRecords? {
        let text = " " + question.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'s ", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator: " ") + " "
        let named = try tags().filter { tag in
            let name = tag.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator: " ")
            return !name.trimmingCharacters(in: .whitespaces).isEmpty && text.contains(" \(name) ")
        }
        guard !named.isEmpty else { return nil }

        let kind = Self.kindWords.first { words, _ in words.contains { text.contains(" \($0) ") } }?.1
        let ids = named.compactMap(\.id)
        let records = try db.read { db in
            try Record.fetchAll(db, sql: """
                SELECT record.* FROM record
                WHERE (SELECT COUNT(DISTINCT tagId) FROM recordTag
                       WHERE recordTag.recordId = record.id AND tagId IN (\(ids.map { _ in "?" }.joined(separator: ",")))) = ?
                AND (? IS NULL OR kind = ?)
                ORDER BY COALESCE(documentDate, substr(createdAt, 1, 10)) DESC, createdAt DESC
                """, arguments: StatementArguments(ids) + [ids.count, kind?.rawValue, kind?.rawValue])
        }
        return TaggedRecords(tags: named, kind: kind, records: records)
    }

    static let kindWords: [([String], RecordKind)] = [
        (["receipt", "receipts"], .receipt),
        (["statement", "statements"], .statement),
        (["bill", "bills"], .bill),
        (["warranty", "warranties"], .warranty),
        (["manual", "manuals"], .manual),
        (["note", "notes", "voice note", "voice notes"], .item),
    ]
}

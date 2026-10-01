import Foundation
import GRDB

/// A record that matched, with the page to open and the words to point at.
public struct SearchHit: Hashable, Identifiable, Sendable {
    public var record: Record
    /// The best-matching page: where tapping the result should land.
    public var pageId: Int64
    public var pagePosition: Int
    public var snippet: Snippet
    /// How many of the record's pages matched, for "and 3 more pages".
    public var matchingPages: Int

    public var id: UUID { record.id }
}

/// A short excerpt around the match, split into plain and matched runs so the
/// UI can bold the matches without parsing anything.
public struct Snippet: Hashable, Sendable {
    public struct Run: Hashable, Sendable {
        public var text: String
        public var isMatch: Bool
    }

    public var runs: [Run]

    public var text: String { runs.map(\.text).joined() }

    static let open: Character = "\u{1}"
    static let close: Character = "\u{2}"

    /// Parses the output of FTS5's `snippet()` called with the markers above.
    init(marked: String) {
        var runs: [Run] = []
        var current = ""
        var inMatch = false
        func flush() {
            if !current.isEmpty { runs.append(Run(text: current, isMatch: inMatch)) }
            current = ""
        }
        for character in marked {
            switch character {
            case Self.open: flush(); inMatch = true
            case Self.close: flush(); inMatch = false
            default: current.append(character)
            }
        }
        flush()
        self.runs = runs
    }
}

extension ArchiveStore {
    /// Full-text search over page text and titles, best match first, one hit
    /// per record. Words are ANDed and each one matches as a prefix, so
    /// "warrant tv" finds "Warranty ... TV". Whatever the person types is
    /// quoted before it reaches FTS5, so no input is a syntax error.
    /// `kind` narrows to one category; nil searches everything.
    public func search(_ text: String, kind: RecordKind? = nil, limit: Int = 50) throws -> [SearchHit] {
        guard let match = Self.matchExpression(for: text) else { return [] }

        return try db.read { db in
            // Ranked per page; a record can appear several times. Fetched with
            // headroom so collapsing to one per record still fills `limit`.
            let rows = try Row.fetchAll(db, sql: """
                SELECT page.id AS pageId, page.recordId AS recordId, page.position AS pagePosition,
                       snippet(searchIndex, -1, char(1), char(2), '…', 16) AS snippet
                FROM searchIndex
                JOIN page ON page.id = searchIndex.rowid
                JOIN record ON record.id = page.recordId
                WHERE searchIndex MATCH ? AND (? IS NULL OR record.kind = ?)
                ORDER BY bm25(searchIndex, 4.0, 1.0)
                LIMIT ?
                """, arguments: [match, kind?.rawValue, kind?.rawValue, limit * 10])

            var order: [UUID] = []
            var best: [UUID: Row] = [:]
            var counts: [UUID: Int] = [:]
            for row in rows {
                let recordId: UUID = row["recordId"]
                counts[recordId, default: 0] += 1
                if best[recordId] == nil {
                    best[recordId] = row
                    order.append(recordId)
                }
            }
            order = Array(order.prefix(limit))

            let records = try Record.fetchAll(db, keys: order)
            let byId = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })

            return order.compactMap { id in
                guard let record = byId[id], let row = best[id] else { return nil }
                return SearchHit(record: record,
                                 pageId: row["pageId"],
                                 pagePosition: row["pagePosition"],
                                 snippet: Snippet(marked: row["snippet"]),
                                 matchingPages: counts[id] ?? 1)
            }
        }
    }

    /// Turns typed words into an FTS5 query: each word quoted as a phrase (so
    /// "12.50" or "AT&T" mean what they look like) and marked as a prefix.
    /// Returns nil when nothing searchable is left, e.g. "$" or "--".
    static func matchExpression(for text: String) -> String? {
        let terms = text
            .split(whereSeparator: \.isWhitespace)
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
        guard !terms.isEmpty else { return nil }
        return terms.map { "\"\($0)\"*" }.joined(separator: " ")
    }
}

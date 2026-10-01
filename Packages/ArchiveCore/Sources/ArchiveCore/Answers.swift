import Foundation
import GRDB

/// One amount that went into an answer, with the record it was read from.
public struct Counted: Hashable, Identifiable, Sendable {
    public var transaction: Amount
    public var record: Record
    public var id: Int64 { transaction.id ?? -1 }

    /// The amount's own date, else the record's.
    public var day: Day { transaction.date ?? record.effectiveDay }
}

/// The same purchase seen twice: a receipt and its line on a statement.
/// Only `kept` is counted.
public struct Duplicate: Hashable, Identifiable, Sendable {
    public var kept: Counted
    public var dropped: Counted
    /// What the person said: true for the same purchase, false for two
    /// different ones, nil while it's only a guess.
    public var decision: Bool?

    public var id: String { "\(kept.id)-\(dropped.id)" }
}

extension Amount {
    /// Names an amount in a way that survives its record being read again,
    /// which replaces row ids: where it was printed, and how much.
    var decisionKey: String {
        if let pagePosition, let linePosition { return "p\(pagePosition):\(linePosition):\(amountCents)" }
        return "id\(id ?? -1):\(amountCents)"
    }
}

/// The decisions a person made about possible duplicates.
struct DuplicateDecisions {
    var byPair: [String: Bool] = [:]

    static func key(_ original: Amount, _ line: Amount) -> String {
        "\(original.recordId.uuidString)|\(original.decisionKey)|\(line.recordId.uuidString)|\(line.decisionKey)"
    }

    func decision(_ original: Amount, _ line: Amount) -> Bool? {
        byPair[Self.key(original, line)]
    }
}

public struct SpendingAnswer: Sendable {
    public var query: SpendingQuery
    /// One per currency, largest first. Empty when nothing matched.
    public var totals: [Money]
    /// What was added up, newest first.
    public var counted: [Counted]
    public var duplicates: [Duplicate]
    public var notes: [String]
    /// When a period was asked about: other months with matching spending,
    /// newest first, so an empty answer can say where there is some.
    public var otherMonths: [MonthTotal] = []
}

/// Matching spending in one calendar month.
public struct MonthTotal: Hashable, Sendable {
    public var range: DayRange
    public var label: String
    public var totals: [Money]
    public var count: Int
}

public struct ExpiryFinding: Hashable, Sendable {
    public var record: Record
    public var day: Day
    /// The printed line the date came from.
    public var evidence: String
    /// Worked out from a purchase date and a coverage length, rather than
    /// printed as an expiry date.
    public var isCalculated: Bool
}

extension ArchiveStore {
    /// Adds up spending from stored amounts. The total is a sum of integer
    /// cents done here, never by a language model; every amount in it is in
    /// `counted` with the record it came from.
    public func answer(_ query: SpendingQuery) throws -> SpendingAnswer {
        let unreadStatements = try db.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM record WHERE kind = ? AND status = ?
                AND NOT EXISTS (SELECT 1 FROM txn WHERE txn.recordId = record.id)
                """, arguments: [RecordKind.statement.rawValue, IngestStatus.ready.rawValue]) ?? 0
        }
        let all = try db.read { db -> [Counted] in
            let rows = try Row.fetchAll(db, sql: """
                SELECT txn.* FROM txn JOIN record ON record.id = txn.recordId
                WHERE txn.kind != 'payment'
                """)
            let recordIds = Set(rows.map { $0["recordId"] as UUID })
            let records = try Record.fetchAll(db, keys: Array(recordIds))
            let byId = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            return try rows.compactMap { row in
                let transaction = try Amount(row: row)
                return byId[transaction.recordId].map { Counted(transaction: transaction, record: $0) }
            }
        }
        let decisions = try duplicateDecisions()

        var matching = all.filter { matches($0, query) }
        let duplicates = Self.duplicates(in: matching, decisions: decisions)
        let droppedIds = Set(duplicates.map(\.dropped.id))
        matching.removeAll { droppedIds.contains($0.id) }
        matching.sort { ($0.day, $0.id) > ($1.day, $1.id) }
        let totals = Self.totals(of: matching)

        var notes = query.notes
        let refunds = matching.filter { $0.transaction.kind == .refund }
        if !refunds.isEmpty {
            notes.append(refunds.count == 1 ? "Includes 1 refund, subtracted." : "Includes \(refunds.count) refunds, subtracted.")
        }
        let rejected = try possibleDuplicates().filter { $0.decision == false && matches($0.dropped, query) }
        if !rejected.isEmpty {
            notes.append(rejected.count == 1
                ? "1 statement line looks like a saved receipt, but you said they're different purchases, so both count."
                : "\(rejected.count) statement lines look like saved receipts, but you said they're different purchases, so both count.")
        }
        if !duplicates.isEmpty {
            notes.append(duplicates.count == 1
                ? "1 purchase appears on both a receipt and a statement; it's counted once."
                : "\(duplicates.count) purchases appear on both a receipt and a statement; each is counted once.")
        }
        if unreadStatements > 0 {
            notes.append(unreadStatements == 1
                ? "1 statement in your archive has no transactions read from it yet, so it isn't counted. Open it to check or add them."
                : "\(unreadStatements) statements in your archive have no transactions read from them yet, so they aren't counted. Open them to check or add them.")
        }
        var otherMonths: [MonthTotal] = []
        if let range = query.range, let label = query.rangeLabel {
            let statementsCover = all.contains { $0.transaction.source == .statement && range.contains($0.day) }
            if !statementsCover {
                let covered = Self.months(of: all.filter { $0.transaction.source == .statement }).map(\.label)
                let which = covered.isEmpty ? "" : " Your statements cover \(Self.list(covered))."
                notes.append("No card or bank statement in your archive covers \(label), so this only counts receipts and bills you've saved.\(which)")
            }
            otherMonths = otherMonthsWithSpending(all, query: query, excluding: range, decisions: decisions)
        }
        return SpendingAnswer(query: query, totals: totals, counted: matching, duplicates: duplicates, notes: notes,
                              otherMonths: otherMonths)
    }

    /// The same question without the date, month by month, deduplicated the
    /// same way. Newest four.
    private func otherMonthsWithSpending(_ all: [Counted], query: SpendingQuery, excluding range: DayRange,
                                         decisions: DuplicateDecisions) -> [MonthTotal] {
        var anyTime = query
        anyTime.range = nil
        var items = all.filter { matches($0, anyTime) && !range.contains($0.day) }
        let dropped = Set(Self.duplicates(in: items, decisions: decisions).map(\.dropped.id))
        items.removeAll { dropped.contains($0.id) }
        return Self.months(of: items).prefix(4).map { month in
            let inMonth = items.filter { month.range.contains($0.day) }
            return MonthTotal(range: month.range, label: month.label, totals: Self.totals(of: inMonth), count: inMonth.count)
        }
    }

    /// Distinct calendar months the items fall in, newest first.
    static func months(of items: [Counted]) -> [(range: DayRange, label: String)] {
        let keys = Set(items.map { $0.day.year * 100 + $0.day.month }).sorted(by: >)
        return keys.compactMap { key in
            DayRange.month(key % 100, of: key / 100).map { ($0, QuestionParser.monthLabel(key % 100, key / 100)) }
        }
    }

    static func totals(of items: [Counted]) -> [Money] {
        var byCurrency: [String: Int64] = [:]
        for item in items {
            byCurrency[item.transaction.currency, default: 0] += item.transaction.spendCents
        }
        return byCurrency.map { Money(cents: $0.value, currency: $0.key) }.sorted { abs($0.cents) > abs($1.cents) }
    }

    static func list(_ words: [String]) -> String {
        switch words.count {
        case 0: ""
        case 1: words[0]
        default: words.dropLast().joined(separator: ", ") + " and " + words.last!
        }
    }

    private func matches(_ item: Counted, _ query: SpendingQuery) -> Bool {
        if let range = query.range, !range.contains(item.day) { return false }
        if !query.categories.isEmpty, !query.categories.contains(item.transaction.category) { return false }
        if !query.merchantTerms.isEmpty {
            let haystack = "\(item.transaction.merchant) \(item.transaction.memo) \(item.record.title)".lowercased()
            if !query.merchantTerms.contains(where: { haystack.contains($0) }) { return false }
        }
        return true
    }

    /// A statement line duplicates a receipt or bill when the amount is the
    /// same to the cent, it posted within a few days of the purchase (bills
    /// within six weeks, since they're paid later), and the merchant looks
    /// the same. The receipt is kept: it has more detail. A pair the person
    /// called different is never matched; one they called the same always is.
    static func duplicates(in items: [Counted], decisions: DuplicateDecisions = DuplicateDecisions(),
                           honoringRejections: Bool = true) -> [Duplicate] {
        let originals = items.filter { $0.transaction.source != .statement }
        var used = Set<Int64>()
        var found: [Duplicate] = []
        for line in items where line.transaction.source == .statement {
            let match = originals.first { original in
                guard !used.contains(original.id),
                      original.transaction.amountCents == line.transaction.amountCents,
                      original.transaction.currency == line.transaction.currency else { return false }
                switch decisions.decision(original.transaction, line.transaction) {
                case true?: return true
                case false?: if honoringRejections { return false }
                case nil: break
                }
                guard (original.transaction.kind == .refund) == (line.transaction.kind == .refund) else { return false }
                let gap = original.day.days(to: line.day)
                let window = original.transaction.source == .bill ? -3...45 : -2...7
                guard window.contains(gap) else { return false }
                return sameMerchant(original.transaction, line.transaction)
            }
            if let match {
                used.insert(match.id)
                found.append(Duplicate(kept: match, dropped: line,
                                       decision: decisions.decision(match.transaction, line.transaction)))
            }
        }
        return found
    }

    func duplicateDecisions() throws -> DuplicateDecisions {
        try db.read { db in
            var decisions = DuplicateDecisions()
            for row in try Row.fetchAll(db, sql: "SELECT * FROM duplicateDecision") {
                let key = "\((row["originalRecordId"] as UUID).uuidString)|\(row["originalKey"] as String)|"
                    + "\((row["lineRecordId"] as UUID).uuidString)|\(row["lineKey"] as String)"
                decisions.byPair[key] = row["isSame"]
            }
            return decisions
        }
    }

    /// Possible duplicates that involve a record (or every one, for nil),
    /// including those already decided, so a decision can be changed.
    public func possibleDuplicates(involving recordId: UUID? = nil) throws -> [Duplicate] {
        let all = try db.read { db -> [Counted] in
            let amounts = try Amount.filter(Column("kind") != AmountKind.payment.rawValue).fetchAll(db)
            let records = try Record.fetchAll(db, keys: Array(Set(amounts.map(\.recordId))))
            let byId = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            return amounts.compactMap { amount in byId[amount.recordId].map { Counted(transaction: amount, record: $0) } }
        }
        return Self.duplicates(in: all, decisions: try duplicateDecisions(), honoringRejections: false)
            .filter { recordId == nil || $0.kept.record.id == recordId || $0.dropped.record.id == recordId }
            .sorted { $0.kept.day > $1.kept.day }
    }

    /// Records whether two amounts are the same purchase; nil forgets it,
    /// so the guess applies again.
    public func decide(_ duplicate: Duplicate, isSame: Bool?) throws {
        let original = duplicate.kept.transaction
        let line = duplicate.dropped.transaction
        try db.write { db in
            let arguments: StatementArguments = [original.recordId, original.decisionKey, line.recordId, line.decisionKey]
            if let isSame {
                try db.execute(sql: """
                    INSERT INTO duplicateDecision (originalRecordId, originalKey, lineRecordId, lineKey, isSame)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(originalRecordId, originalKey, lineRecordId, lineKey) DO UPDATE SET isSame = excluded.isSame
                    """, arguments: arguments + [isSame])
            } else {
                try db.execute(sql: """
                    DELETE FROM duplicateDecision
                    WHERE originalRecordId = ? AND originalKey = ? AND lineRecordId = ? AND lineKey = ?
                    """, arguments: arguments)
            }
        }
    }

    static func sameMerchant(_ a: Amount, _ b: Amount) -> Bool {
        if a.category == b.category, a.category != .other { return true }
        let words = { (t: Amount) in
            Set(t.merchant.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 3 })
        }
        return !words(a).isDisjoint(with: words(b))
    }

    /// Best matches for "where is …", items and notes first.
    public func whereIs(_ terms: [String]) throws -> [SearchHit] {
        guard !terms.isEmpty else { return [] }
        let text = terms.joined(separator: " ")
        let items = try search(text, kind: .item, limit: 5)
        if !items.isEmpty { return items }
        // Fewer words, in case one of them isn't in the note.
        let loose = try terms.flatMap { try search($0, kind: .item, limit: 5) }
        if !loose.isEmpty { return Array(Dictionary(grouping: loose, by: \.id).compactMap(\.value.first).prefix(5)) }
        return try search(text, limit: 5)
    }

    /// Expiry dates on warranties (and anything else) matching `terms`:
    /// printed ones first, then ones worked out from "purchased" plus
    /// "N year(s)" coverage.
    public func expiries(_ terms: [String]) throws -> [ExpiryFinding] {
        var candidates: [Record] = []
        if !terms.isEmpty {
            var hits = try search(terms.joined(separator: " "))
            if hits.isEmpty { hits = try terms.flatMap { try search($0) } }
            let matched: [Record] = hits.map(\.record)
            let warranties = matched.filter { $0.kind == .warranty }
            let others = matched.filter { $0.kind != .warranty }
            var seen = Set<UUID>()
            candidates = (warranties + others).filter { seen.insert($0.id).inserted }
        }
        // Nothing mentions it, or nothing was named: every warranty.
        if candidates.isEmpty {
            candidates = try records(kind: .warranty)
        }
        return try db.read { db in
            try candidates.compactMap { record in
                let rows = Extractor.rows(of: try Self.storedPages(of: record.id, in: db))
                return Self.expiry(in: rows, record: record)
            }
        }
    }

    static func expiry(in rows: [TextRow], record: Record) -> ExpiryFinding? {
        for row in rows {
            let lower = row.text.lowercased()
            if ["expir", "valid until", "valid thru", "coverage ends", "warranty ends", "ends on"].contains(where: { lower.contains($0) }),
               let day = DayParser.firstDay(in: row.text) {
                return ExpiryFinding(record: record, day: day, evidence: row.text, isCalculated: false)
            }
        }
        let purchased = rows.first { $0.text.lowercased().contains("purchase") }.flatMap { DayParser.firstDay(in: $0.text) }
            ?? record.documentDate
        let lengthRegex = DayParser.regex("(\\d{1,2})\\s*-?\\s*(year|yr|month|mo)s?\\b")
        for row in rows {
            let ns = row.text as NSString
            guard let start = purchased,
                  let match = lengthRegex.firstMatch(in: row.text, range: NSRange(location: 0, length: ns.length)),
                  let count = Int(ns.substring(with: match.range(at: 1))) else { continue }
            let isYears = ns.substring(with: match.range(at: 2)).lowercased().hasPrefix("y")
            let months = isYears ? count * 12 : count
            var month = start.month + months
            var year = start.year
            while month > 12 { month -= 12; year += 1 }
            let day = Day(year: year, month: month, day: start.day) ?? Day(year: year, month: month, day: 28)
            guard let day else { continue }
            return ExpiryFinding(record: record, day: day, evidence: row.text, isCalculated: true)
        }
        return nil
    }
}

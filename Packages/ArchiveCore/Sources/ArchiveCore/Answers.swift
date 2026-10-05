import Foundation
import GRDB

/// One amount that went into an answer, with the record it was read from.
public struct Counted: Hashable, Identifiable, Sendable {
    public var transaction: Amount
    public var record: Record
    /// The record's people and places, so "spent in Boston" can match.
    public var tagNames: [String] = []
    public var id: Int64 { transaction.id ?? -1 }

    /// What merchant words are looked for in.
    var haystack: String {
        ([transaction.merchant, transaction.memo, record.title] + tagNames).joined(separator: " ").lowercased()
    }

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
    /// For "what did I get…": each counted receipt's lines, newest receipt first.
    public var itemsByRecord: [(record: Record, items: [LineItem])] = []
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
        let untagged = try db.read { db -> [Counted] in
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
        let all = try withTags(untagged)
        let decisions = try duplicateDecisions()

        // Words that aren't any saved merchant ("set back over") are dropped
        // when a category says what was meant; on their own they stay, so
        // "at Starbucks" with no Starbucks is an honest nothing.
        var query = query
        // A word that isn't in any store's name may still be printed on the
        // receipt: "Licensed cannabis dispensary" under a shop's own name.
        var unknown: [String] = []
        for term in Self.unknownTerms(query.merchantTerms, in: all) {
            // A thing on a receipt's lines ("eggs") counts as that line, not the whole receipt.
            if try !itemAmounts(matching: [term]).isEmpty { continue }
            let printing = try recordsPrinting(term)
            if printing.isEmpty { unknown.append(term) }
            query.textMatchedRecords.formUnion(printing)
        }
        if !unknown.isEmpty, !query.categories.isEmpty {
            query.merchantTerms.removeAll { unknown.contains($0) }
            query.notes.append("Didn't match \(Self.list(unknown.map { "“\($0)”" })) to any saved store, so \(unknown.count == 1 ? "it was" : "they were") left out.")
        }

        var matching = all.filter { matches($0, query) }
        // "At the dispensary" read as pharmacy spending: when the place has
        // amounts but none in that category, the place is what was meant.
        if matching.isEmpty, !query.categories.isEmpty, !query.merchantTerms.isEmpty {
            var anyCategory = query
            anyCategory.categories = []
            let found = all.filter { matches($0, anyCategory) }
            if !found.isEmpty {
                let names = query.categories.map(\.rawValue).sorted()
                anyCategory.notes.append("Nothing at \(Self.list(query.merchantTerms.map { "“\($0)”" })) is filed as \(Self.list(names)), so everything there was counted.")
                query = anyCategory
                matching = found
            }
        }
        // "Eggs" isn't a store: lines on receipts that name it count too,
        // except on receipts whose whole total already matched.
        var itemCount = 0
        if !query.merchantTerms.isEmpty {
            let whole = Set(matching.filter { $0.transaction.source != .statement }.map(\.record.id))
            let items = try itemAmounts(matching: query.merchantTerms, except: whole).filter { matches($0, query) }
            itemCount = items.count
            matching += items
        }
        // Duplicates are looked for across all dates: a receipt from the
        // 30th and its card line posted on the 2nd are one purchase, made in
        // the receipt's month.
        var pool = matching
        if query.range != nil {
            var anyDate = query
            anyDate.range = nil
            // Receipt items (negative ids) are already in `matching`.
            pool = all.filter { matches($0, anyDate) } + matching.filter { $0.id < 0 }
        }
        let matchingIds = Set(matching.map(\.id))
        let duplicates = Self.duplicates(in: pool, decisions: decisions)
            .filter { matchingIds.contains($0.dropped.id) }
        let droppedIds = Set(duplicates.map(\.dropped.id))
        matching.removeAll { droppedIds.contains($0.id) }
        matching.sort { ($0.day, $0.id) > ($1.day, $1.id) }
        let totals = Self.totals(of: matching)

        var notes = query.notes
        if itemCount > 0 {
            notes.append(itemCount == 1 ? "Includes 1 item from a receipt's lines." : "Includes \(itemCount) items from receipts' lines.")
        }
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
                ? "1 purchase appears twice (on a receipt and a statement, or on two statements); it's counted once."
                : "\(duplicates.count) purchases appear twice (on a receipt and a statement, or on two statements); each is counted once.")
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
        var itemsByRecord: [(record: Record, items: [LineItem])] = []
        if query.listsItems {
            var seen = Set<UUID>()
            for item in matching where item.transaction.source != .statement && seen.insert(item.record.id).inserted {
                let lines = try items(of: item.record.id)
                if !lines.isEmpty { itemsByRecord.append((item.record, lines)) }
            }
            if itemsByRecord.isEmpty, !matching.isEmpty {
                notes.append("No item lines could be read from these, so only the totals are shown. Card statements don't list items.")
            }
        }
        return SpendingAnswer(query: query, totals: totals, counted: matching, duplicates: duplicates, notes: notes,
                              otherMonths: otherMonths, itemsByRecord: itemsByRecord)
    }

    /// Merchant words that appear in no saved amount, its line, its record,
    /// or the printed text of a receipt or bill.
    public func unknownMerchantTerms(_ terms: [String]) throws -> [String] {
        guard !terms.isEmpty else { return [] }
        return try db.read { db in
            try terms.filter { term in
                let pattern = "%\(term)%"
                return try !(Bool.fetchOne(db, sql: """
                    SELECT EXISTS (SELECT 1 FROM txn JOIN record ON record.id = txn.recordId
                    WHERE txn.merchant LIKE ? OR txn.memo LIKE ? OR record.title LIKE ?
                       OR EXISTS (SELECT 1 FROM recordTag JOIN tag ON tag.id = recordTag.tagId
                                  WHERE recordTag.recordId = record.id AND tag.name LIKE ?))
                    """, arguments: [pattern, pattern, pattern, pattern]) ?? false)
            }
        }
        .filter { try recordsPrinting($0).isEmpty }
    }

    func withTags(_ items: [Counted]) throws -> [Counted] {
        let tags = try tagsByRecord()
        guard !tags.isEmpty else { return items }
        return items.map { item in
            var item = item
            item.tagNames = tags[item.record.id]?.map(\.name) ?? []
            return item
        }
    }

    /// `word` in `text` as a whole word or phrase: "car wash" yes, "card" no.
    static func containsWord(_ text: String, _ word: String) -> Bool {
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: word, options: .caseInsensitive, range: range) {
            let before = found.lowerBound == text.startIndex ? nil : text[text.index(before: found.lowerBound)]
            let after = found.upperBound == text.endIndex ? nil : text[found.upperBound]
            if !(before?.isLetter ?? false) && !(after?.isLetter ?? false) { return true }
            range = found.upperBound..<text.endIndex
        }
        return false
    }

    static func unknownTerms(_ terms: [String], in items: [Counted]) -> [String] {
        terms.filter { term in !items.contains { $0.haystack.contains(term) } }
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

    /// Receipts and bills (not statements) whose text has `term`.
    func recordsPrinting(_ term: String) throws -> Set<UUID> {
        Set(try search(term, limit: 500).map(\.record).filter { $0.kind != .statement }.map(\.id))
    }

    private func matches(_ item: Counted, _ query: SpendingQuery) -> Bool {
        if let only = query.onlyRecords, !only.contains(item.record.id) {
            // A statement line can still belong by what it says.
            guard item.transaction.source == .statement,
                  query.lineKeywords.contains(where: { Self.containsWord(item.haystack, $0) }) else { return false }
        }
        if let range = query.range, !range.contains(item.day) { return false }
        if !query.categories.isEmpty, !query.categories.contains(item.transaction.category) { return false }
        if !query.merchantTerms.isEmpty {
            let haystack = item.haystack
            let printed = item.transaction.source != .statement && query.textMatchedRecords.contains(item.record.id)
            if !printed, !query.merchantTerms.contains(where: { haystack.contains($0) }) { return false }
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
        // Only the same amount can match, so each line looks only at those.
        let originals = Dictionary(grouping: items.filter { $0.transaction.source != .statement }, by: AmountKey.init)
        var used = Set<Int64>()
        var found: [Duplicate] = []
        for line in items where line.transaction.source == .statement {
            let match = originals[AmountKey(line)]?.first { original in
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
        let overlaps = statementOverlaps(in: items, excluding: Set(found.map(\.dropped.id)), decisions: decisions,
                                         honoringRejections: honoringRejections)
        let taken = Set((found + overlaps).flatMap { [$0.kept.id, $0.dropped.id] })
        return found + overlaps + repeatedReceipts(in: items, excluding: taken, decisions: decisions,
                                                   honoringRejections: honoringRejections)
    }

    /// The same receipt or bill saved twice: photographed again, or shared
    /// in after a scan. Same total, same day, same store, different records.
    /// The one saved first is kept.
    static func repeatedReceipts(in items: [Counted], excluding taken: Set<Int64>, decisions: DuplicateDecisions,
                                 honoringRejections: Bool) -> [Duplicate] {
        let originals = items.filter { ($0.transaction.source == .receipt || $0.transaction.source == .bill) && $0.id >= 0
            && !taken.contains($0.id) }
            .sorted { ($0.record.createdAt, $0.id) < ($1.record.createdAt, $1.id) }
        var used = Set<Int64>()
        var found: [Duplicate] = []
        for originals in Dictionary(grouping: originals, by: AmountKey.init).values {
        for (index, first) in originals.enumerated() where !used.contains(first.id) {
            for other in originals[(index + 1)...] where !used.contains(other.id) && other.record.id != first.record.id {
                guard other.transaction.amountCents == first.transaction.amountCents,
                      other.transaction.currency == first.transaction.currency,
                      other.transaction.kind == first.transaction.kind else { continue }
                let decision = decisions.decision(first.transaction, other.transaction)
                if decision == false, honoringRejections { continue }
                guard decision == true || (first.day == other.day && sameMerchant(first.transaction, other.transaction))
                else { continue }
                used.insert(other.id)
                found.append(Duplicate(kept: first, dropped: other, decision: decision))
                break
            }
        }
        }
        return found.sorted { ($0.kept.record.createdAt, $0.kept.id) < ($1.kept.record.createdAt, $1.kept.id) }
    }

    /// The same charge on two statements: a card's CSV export and its PDF
    /// for the same month, or one statement imported twice. Same amount,
    /// within two days, same merchant, on different records. The line from
    /// the record imported first is kept.
    static func statementOverlaps(in items: [Counted], excluding taken: Set<Int64>, decisions: DuplicateDecisions,
                                  honoringRejections: Bool) -> [Duplicate] {
        let lines = items.filter { $0.transaction.source == .statement && !taken.contains($0.id) }
            .sorted { ($0.record.createdAt, $0.id) < ($1.record.createdAt, $1.id) }
        var used = Set<Int64>()
        var found: [Duplicate] = []
        for lines in Dictionary(grouping: lines, by: AmountKey.init).values {
        for (index, line) in lines.enumerated() where !used.contains(line.id) {
            for other in lines[(index + 1)...] where !used.contains(other.id) && other.record.id != line.record.id {
                guard other.transaction.amountCents == line.transaction.amountCents,
                      other.transaction.currency == line.transaction.currency,
                      (other.transaction.kind == .refund) == (line.transaction.kind == .refund) else { continue }
                let decision = decisions.decision(line.transaction, other.transaction)
                if decision == false, honoringRejections { continue }
                guard decision == true || (abs(line.day.days(to: other.day)) <= 2 && sameMerchant(line.transaction, other.transaction))
                else { continue }
                used.insert(other.id)
                found.append(Duplicate(kept: line, dropped: other, decision: decision))
                break
            }
        }
        }
        return found.sorted { ($0.kept.record.createdAt, $0.kept.id) < ($1.kept.record.createdAt, $1.kept.id) }
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

    /// Whether two amounts look like the same store: a shared word
    /// ("Mario's Pizzeria" and "MARIOS PIZZA"), or one name the start of the
    /// other once spaces go ("WHOLEFDS" and "Whole Foods", "PG&E" and
    /// "PGANDE"). A statement line's description counts too. Two places in
    /// the same category aren't enough on their own.
    static func sameMerchant(_ a: Amount, _ b: Amount) -> Bool {
        func names(_ t: Amount) -> [String] {
            t.source == .statement && !t.memo.isEmpty && t.memo != t.merchant ? [t.merchant, t.memo] : [t.merchant]
        }
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().replacingOccurrences(of: "'", with: "").split { !$0.isLetter }.map(String.init)
                .filter { $0.count >= 3 && !genericWords.contains($0) })
        }
        func compact(_ text: String) -> String {
            text.lowercased().replacingOccurrences(of: "&", with: "and").filter { $0.isLetter }
        }
        for x in names(a) {
            for y in names(b) {
                if !words(x).isDisjoint(with: words(y)) { return true }
                let (p, q) = (compact(x), compact(y))
                let (short, long) = p.count <= q.count ? (p, q) : (q, p)
                guard short.count >= 3 else { continue }
                if long.hasPrefix(short) || zip(p, q).prefix { $0 == $1 }.count >= 5 { return true }
            }
        }
        return false
    }

    /// Words on statement lines that say nothing about which store it was.
    static let genericWords: Set<String> = [
        "the", "and", "inc", "llc", "ltd", "corp", "com", "www", "store", "stores", "shop", "market", "pos", "purchase",
        "debit", "credit", "card", "online", "payment", "pymt", "ach", "web", "recurring", "autopay", "bill", "sale",
        "usa", "intl", "restaurant", "cafe", "bar", "grill", "kitchen", "pizza", "coffee", "gas", "station", "pharmacy",
        "apple", "pay", "square", "sumup", "toast", "paypal", "venmo",
    ]

    /// Amounts that could be the same purchase: same cents, same currency.
    struct AmountKey: Hashable {
        let cents: Int64
        let currency: String
        init(_ item: Counted) {
            cents = item.transaction.amountCents
            currency = item.transaction.currency
        }
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

    /// Words that come before an end date. "exp" needs a gap or a colon
    /// after it so "expenses" doesn't count.
    static let expiryLabels = ["expir", "exp ", "exp:", "exp.", "valid until", "valid thru", "valid through",
                               "coverage ends", "warranty ends", "ends on", "renew by", "renewal date", "date of expiration"]
    /// Labels for a period whose end is the expiry: "Policy period
    /// 10/01/2026 to 10/01/2027".
    static let periodLabels = ["policy period", "coverage period", "policy term", "lease term", "term:", "effective"]

    /// The date after an expiry label (not an issue date earlier on the same
    /// row), or the last date of a labelled period.
    static func printedExpiry(in rows: [TextRow]) -> (day: Day, row: String)? {
        for row in rows {
            let lower = row.text.lowercased()
            let days = DayParser.days(in: row.text)
            guard !days.isEmpty else { continue }
            if let label = expiryLabels.compactMap({ lower.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
                let offset = lower.distance(from: lower.startIndex, to: label.lowerBound)
                if let day = days.first(where: { $0.range.location >= offset })?.day ?? days.last?.day {
                    return (day, row.text)
                }
            }
            if periodLabels.contains(where: { lower.contains($0) }), days.count >= 2, let last = days.map(\.day).max() {
                return (last, row.text)
            }
        }
        return nil
    }

    static func expiry(in rows: [TextRow], record: Record) -> ExpiryFinding? {
        if let printed = printedExpiry(in: rows) {
            return ExpiryFinding(record: record, day: printed.day, evidence: printed.row, isCalculated: false)
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

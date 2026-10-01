import Foundation
import GRDB

public enum TransactionKind: String, Codable, CaseIterable, Sendable {
    /// Money out: a receipt's total or a card purchase.
    case purchase
    /// A bill's amount due.
    case bill
    /// Interest or a fee on a statement.
    case fee
    /// Money back: a return or credit.
    case refund
    /// Paying the card off. Not spending, so never counted in totals.
    case payment
}

public enum TransactionSource: String, Codable, Sendable {
    case receipt, bill, statement, person
}

/// What money went on, for questions like "how much on gas".
public enum SpendCategory: String, Codable, CaseIterable, Sendable {
    case fuel, groceries, dining, pharmacy, utilities, subscriptions, shopping, travel, other
}

/// One amount read from a record: a receipt's total, a bill's amount due, or
/// a line on a statement. It remembers where on the record it was printed,
/// so every answer that uses it can point back to the original.
public struct Transaction: Codable, Hashable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "txn"

    public var id: Int64?
    public var recordId: UUID
    /// Where it was printed: the page's position in the record and the
    /// line's position on that page. Nil for amounts a person typed in.
    public var pagePosition: Int?
    public var linePosition: Int?
    public var date: Day?
    /// Cleaned up: "Shell", not "SHELL OIL 57442".
    public var merchant: String
    /// As printed.
    public var memo: String
    /// Always positive; `kind` says which way the money went.
    public var amountCents: Int64
    public var currency: String
    public var kind: TransactionKind
    public var category: SpendCategory
    public var source: TransactionSource
    /// Corrected by a person: kept when the record's text is read again.
    public var isEdited: Bool

    public init(id: Int64? = nil, recordId: UUID, pagePosition: Int? = nil, linePosition: Int? = nil,
                date: Day?, merchant: String, memo: String = "", amountCents: Int64, currency: String = "USD",
                kind: TransactionKind, category: SpendCategory? = nil, source: TransactionSource,
                isEdited: Bool = false) {
        self.id = id
        self.recordId = recordId
        self.pagePosition = pagePosition
        self.linePosition = linePosition
        self.date = date
        self.merchant = merchant
        self.memo = memo
        self.amountCents = amountCents
        self.currency = currency
        self.kind = kind
        self.category = category ?? SpendCategories.classify(merchant: merchant, memo: memo)
        self.source = source
        self.isEdited = isEdited
    }

    /// What it adds to "how much did I spend": purchases, bills and fees
    /// count, refunds subtract, payments are neither.
    public var spendCents: Int64 {
        switch kind {
        case .purchase, .bill, .fee: amountCents
        case .refund: -amountCents
        case .payment: 0
        }
    }

    public var money: Money { Money(cents: amountCents, currency: currency) }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Word lists, not a model: predictable, and easy to see why something was
/// counted as fuel.
enum SpendCategories {
    static let keywords: [(SpendCategory, [String])] = [
        (.fuel, ["shell", "chevron", "exxon", "mobil", "sunoco", "speedway", "wawa", "citgo", "marathon",
                 "valero", "arco", "gulf", "phillips 66", "conoco", "circle k", "fuel", "unleaded", "gas station"]),
        (.utilities, ["pg&e", "national grid", "eversource", "con edison", "coned", "duke energy", "xfinity",
                      "comcast", "verizon", "at&t", "t-mobile", "spectrum", "electric", "energy", "water",
                      "utility", "wireless", "internet"]),
        (.pharmacy, ["cvs", "walgreens", "rite aid", "pharmacy"]),
        (.groceries, ["costco", "trader joe", "whole foods", "safeway", "kroger", "publix", "aldi", "stop & shop",
                      "wegmans", "market basket", "h-e-b", "sam's club", "grocery", "supermarket", "foods"]),
        (.dining, ["starbucks", "dunkin", "mcdonald", "chipotle", "panera", "chick-fil-a", "doordash",
                   "uber eats", "grubhub", "restaurant", "cafe", "coffee", "pizza", "grill", "bar ", "kitchen"]),
        (.subscriptions, ["netflix", "spotify", "hulu", "disney", "apple.com/bill", "youtube", "subscription"]),
        (.travel, ["uber", "lyft", "airline", "airlines", "hotel", "airbnb", "delta", "united", "jetblue"]),
        (.shopping, ["amazon", "amzn", "target", "walmart", "best buy", "home depot", "lowe's", "ikea",
                     "apple store", "etsy", "ebay"]),
    ]

    static func classify(merchant: String, memo: String) -> SpendCategory {
        let text = "\(merchant) \(memo)".lowercased()
        for (category, words) in keywords where words.contains(where: { text.contains($0) }) {
            return category
        }
        return .other
    }
}

extension ArchiveStore {
    public func transactions(of recordId: UUID) throws -> [Transaction] {
        try db.read {
            try Transaction.filter(Column("recordId") == recordId)
                .order(Column("pagePosition"), Column("linePosition"), Column("id"))
                .fetchAll($0)
        }
    }

    /// Saves a correction, or a new amount typed by a person, and marks it as
    /// theirs so re-reading the record won't overwrite it.
    public func save(_ transaction: Transaction) throws {
        var transaction = transaction
        transaction.isEdited = true
        if transaction.source != .person {
            transaction.category = SpendCategories.classify(merchant: transaction.merchant, memo: transaction.memo)
        }
        try db.write { db in
            try transaction.save(db)
            try Self.markExtractionEdited(transaction.recordId, in: db)
        }
    }

    public func delete(transaction id: Int64, of recordId: UUID) throws {
        try db.write { db in
            _ = try Transaction.deleteOne(db, key: id)
            try Self.markExtractionEdited(recordId, in: db)
        }
    }

    /// Sets the date a record is about (the receipt's date, a statement's
    /// closing date) by hand.
    public func setDocumentDate(_ day: Day?, for recordId: UUID) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE record SET documentDate = ?, documentDateEdited = 1 WHERE id = ?",
                           arguments: [day?.iso, recordId])
        }
    }

    /// Once anything is corrected by hand, re-reading leaves every amount on
    /// the record alone, so a fix is never lost or duplicated.
    static func markExtractionEdited(_ recordId: UUID, in db: Database) throws {
        try db.execute(sql: "UPDATE txn SET isEdited = 1 WHERE recordId = ?", arguments: [recordId])
    }
}

extension ArchiveStore {
    /// The total of each receipt and bill, for showing on its card.
    /// Statements are left out: their lines aren't one amount.
    public func recordTotals() throws -> [UUID: Money] {
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT recordId, currency,
                       SUM(CASE kind WHEN 'refund' THEN -amountCents WHEN 'payment' THEN 0 ELSE amountCents END) AS cents
                FROM txn WHERE source != 'statement'
                GROUP BY recordId, currency
                """)
            var totals: [UUID: Money] = [:]
            for row in rows {
                let recordId: UUID = row["recordId"]
                // One currency per record in practice; keep the first if not.
                if totals[recordId] == nil {
                    totals[recordId] = Money(cents: row["cents"], currency: row["currency"])
                }
            }
            return totals
        }
    }
}

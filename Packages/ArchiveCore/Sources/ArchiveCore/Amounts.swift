import Foundation
import GRDB

public enum AmountKind: String, Codable, CaseIterable, Sendable {
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

public enum AmountSource: String, Codable, Sendable {
    case receipt, bill, statement, person
}

/// What money went on, for questions like "how much on gas".
public enum SpendCategory: String, Codable, CaseIterable, Sendable {
    case fuel, groceries, dining, pharmacy, utilities, subscriptions, shopping, travel, other
}

/// One amount read from a record: a receipt's total, a bill's amount due, or
/// a line on a statement. It remembers where on the record it was printed,
/// so every answer that uses it can point back to the original.
public struct Amount: Codable, Hashable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
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
    public var kind: AmountKind
    public var category: SpendCategory
    public var source: AmountSource
    /// Corrected by a person: kept when the record's text is read again.
    public var isEdited: Bool
    /// The category was picked by a person for this line alone, so neither
    /// the word lists nor a merchant rule change it.
    public var categoryEdited: Bool

    public init(id: Int64? = nil, recordId: UUID, pagePosition: Int? = nil, linePosition: Int? = nil,
                date: Day?, merchant: String, memo: String = "", amountCents: Int64, currency: String = "USD",
                kind: AmountKind, category: SpendCategory? = nil, source: AmountSource,
                isEdited: Bool = false, categoryEdited: Bool = false) {
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
        self.categoryEdited = categoryEdited
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
                      "wegmans", "market basket", "h-e-b", "sam's club", "grocery", "supermarket", "foods", "wholefds",
                      "whole fds", "trader joes"]),
        (.dining, ["starbucks", "dunkin", "mcdonald", "chipotle", "panera", "chick-fil-a", "doordash",
                   "uber eats", "grubhub", "instacart", "wendy", "burger", "taco bell", "restaurant", "cafe", "coffee",
                   "pizza", "pizzeria", "grill", "bar ", "kitchen", "bistro", "sushi", "bakery", "taqueria", "trattoria",
                   "diner", "eatery", "tst*", "noodle"]),
        (.subscriptions, ["netflix", "spotify", "hulu", "disney", "apple.com/bill", "youtube", "subscription",
                          "prime video", "game pass", "patreon", "membership", "dashpass", "apple"]),
        (.travel, ["uber", "lyft", "airline", "airlines", "hotel", "airbnb", "delta", "united", "jetblue"]),
        (.shopping, ["amazon", "amzn", "target", "walmart", "best buy", "home depot", "lowe's", "ikea",
                     "apple store", "etsy", "ebay"]),
    ]

    /// By the merchant first, then the printed line: a DoorDash order from
    /// CVS is eating out, not pharmacy.
    static func classify(merchant: String, memo: String) -> SpendCategory {
        for text in [merchant.lowercased(), memo.lowercased()] {
            for (category, words) in keywords where words.contains(where: { text.contains($0) }) {
                return category
            }
        }
        return .other
    }
}

extension ArchiveStore {
    public func transactions(of recordId: UUID) throws -> [Amount] {
        try db.read {
            try Amount.filter(Column("recordId") == recordId)
                .order(Column("pagePosition"), Column("linePosition"), Column("id"))
                .fetchAll($0)
        }
    }

    /// Saves a correction, or a new amount typed by a person, and marks it as
    /// theirs so re-reading the record won't overwrite it. A changed category
    /// sticks to this line; otherwise the category follows the merchant.
    public func save(_ transaction: Amount) throws {
        var transaction = transaction
        transaction.isEdited = true
        try db.write { db in
            let stored = try transaction.id.flatMap { try Amount.fetchOne(db, key: $0) }
            if let stored, stored.category != transaction.category {
                transaction.categoryEdited = true
            } else if stored == nil, transaction.source == .person, transaction.category != .other {
                transaction.categoryEdited = true
            }
            if !transaction.categoryEdited {
                transaction.category = try Self.category(merchant: transaction.merchant, memo: transaction.memo, in: db)
            }
            try transaction.save(db)
            try Self.markExtractionEdited(transaction.recordId, in: db)
        }
    }

    /// How many lines, across every record, have this merchant. Lets a
    /// category fix offer to cover all of them.
    public func lineCount(merchant: String) throws -> Int {
        try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM txn WHERE merchant = ? COLLATE NOCASE", arguments: [merchant]) ?? 0
        }
    }

    /// Files every line from `merchant` under `category`, now and whenever a
    /// record is read again, including lines given a category of their own.
    public func setCategory(_ category: SpendCategory, forMerchant merchant: String) throws {
        let name = merchant.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO merchantCategory (merchant, category) VALUES (?, ?)
                ON CONFLICT(merchant) DO UPDATE SET category = excluded.category
                """, arguments: [name, category.rawValue])
            try db.execute(sql: "UPDATE txn SET category = ?, categoryEdited = 0 WHERE merchant = ? COLLATE NOCASE",
                           arguments: [category.rawValue, name])
        }
    }

    /// Category rules a person made, by merchant.
    public func merchantCategories() throws -> [String: SpendCategory] {
        try db.read { try Self.merchantRules(in: $0) }
    }

    static func merchantRules(in db: Database) throws -> [String: SpendCategory] {
        var rules: [String: SpendCategory] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT merchant, category FROM merchantCategory") {
            if let category = SpendCategory(rawValue: row["category"]) {
                rules[(row["merchant"] as String).lowercased()] = category
            }
        }
        return rules
    }

    /// A person's rule for the merchant if there is one, else the word lists.
    static func category(merchant: String, memo: String, in db: Database) throws -> SpendCategory {
        try merchantRules(in: db)[merchant.lowercased()] ?? SpendCategories.classify(merchant: merchant, memo: memo)
    }

    public func delete(transaction id: Int64, of recordId: UUID) throws {
        try db.write { db in
            _ = try Amount.deleteOne(db, key: id)
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

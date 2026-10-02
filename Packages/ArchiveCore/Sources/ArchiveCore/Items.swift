import Foundation
import GRDB

/// One thing bought, read from a line of a receipt. Not counted in totals by
/// itself (the receipt's total already is); it makes "how much did I spend
/// on eggs" and "when did I last buy printer ink" answerable.
public struct LineItem: Codable, Hashable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "lineItem"

    public var id: Int64?
    public var recordId: UUID
    public var pagePosition: Int
    public var linePosition: Int
    public var name: String
    public var amountCents: Int64
    public var currency: String

    public var money: Money { Money(cents: amountCents, currency: currency) }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension ArchiveStore {
    public func items(of recordId: UUID) throws -> [LineItem] {
        try db.read {
            try LineItem.filter(Column("recordId") == recordId)
                .order(Column("pagePosition"), Column("linePosition")).fetchAll($0)
        }
    }

    /// Items whose name has any of `terms`, each as an amount on its
    /// receipt's date, newest first. Receipts whose own total is in `except`
    /// are skipped, so nothing is counted twice.
    func itemAmounts(matching terms: [String], except: Set<UUID> = []) throws -> [Counted] {
        guard !terms.isEmpty else { return [] }
        return try db.read { db in
            let clauses = terms.map { _ in "name LIKE ?" }.joined(separator: " OR ")
            let items = try LineItem.fetchAll(db, sql: "SELECT * FROM lineItem WHERE \(clauses)",
                                              arguments: StatementArguments(terms.map { "%\($0)%" }))
                .filter { !except.contains($0.recordId) }
            let records = try Record.fetchAll(db, keys: Array(Set(items.map(\.recordId))))
            let byId = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            return try items.compactMap { item -> Counted? in
                guard let record = byId[item.recordId], let itemId = item.id else { return nil }
                let receiptTotal = try Amount.filter(Column("recordId") == item.recordId && Column("source") == AmountSource.receipt.rawValue)
                    .fetchOne(db)
                let amount = Amount(
                    id: -itemId, recordId: item.recordId, pagePosition: item.pagePosition, linePosition: item.linePosition,
                    date: receiptTotal?.date ?? record.documentDate, merchant: receiptTotal?.merchant ?? record.title,
                    memo: item.name, amountCents: item.amountCents, currency: item.currency, kind: .purchase,
                    category: receiptTotal?.category, source: .receipt)
                return Counted(transaction: amount, record: record)
            }
            .sorted { ($0.day, $0.id) > ($1.day, $1.id) }
        }
    }

    /// "When did I last buy printer ink": matching items, newest first.
    public func lastBought(_ terms: [String]) throws -> [Counted] {
        try itemAmounts(matching: terms)
    }
}

extension ArchiveStore {
    /// Reads items from receipts saved before items were read. Returns how
    /// many receipts got some.
    @discardableResult
    public func refreshItems() throws -> Int {
        try db.write { db in
            let receipts = try Record.filter([RecordKind.receipt.rawValue, RecordKind.bill.rawValue].contains(Column("kind"))
                                             && Column("status") == IngestStatus.ready.rawValue).fetchAll(db)
            var changed = 0
            for record in receipts {
                let pages = try Self.storedPages(of: record.id, in: db)
                let merchant = Suggester.name(in: pages) ?? record.title
                let items = Extractor.extract(kind: record.kind, pages: pages, recordId: record.id, merchant: merchant).items
                try db.execute(sql: "DELETE FROM lineItem WHERE recordId = ?", arguments: [record.id])
                for var item in items { try item.insert(db) }
                if !items.isEmpty { changed += 1 }
            }
            return changed
        }
    }
}

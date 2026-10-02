import Foundation
import GRDB

/// Spending in one calendar month, by category. Integer cents, with the same
/// duplicate handling as answers: a receipt and its statement line count once.
public struct MonthSpending: Hashable, Identifiable, Sendable {
    public var range: DayRange
    public var label: String
    /// Purchases, bills and fees, less refunds. Payments never count.
    public var totalCents: Int64
    public var byCategory: [SpendCategory: Int64]
    public var count: Int

    public var id: Day { range.start }

    public init(range: DayRange, label: String, totalCents: Int64, byCategory: [SpendCategory: Int64], count: Int) {
        self.range = range
        self.label = label
        self.totalCents = totalCents
        self.byCategory = byCategory
        self.count = count
    }
}

public struct SpendingOverview: Sendable {
    /// The currency most amounts are in; months only add up that one.
    public var currency: String
    /// Oldest first, every month from the first with spending to the last,
    /// including empty ones in between. At most the latest `months`.
    public var months: [MonthSpending]
    /// Amounts in other currencies, left out of the months.
    public var otherCurrencyCount: Int
}

/// A charge that comes back on a schedule: a streaming service, a phone
/// plan, a yearly membership.
public struct RecurringCharge: Hashable, Identifiable, Sendable {
    public enum Cadence: String, Sendable {
        case monthly, yearly
    }

    public var merchant: String
    public var category: SpendCategory
    public var cadence: Cadence
    /// Oldest first.
    public var charges: [Counted]
    public var currency: String

    public var latest: Counted { charges[charges.count - 1] }
    /// What the latest one cost.
    public var typicalCents: Int64 { latest.transaction.amountCents }
    /// What a year of it costs at the latest price.
    public var yearlyCents: Int64 { cadence == .monthly ? typicalCents * 12 : typicalCents }
    public var nextExpected: Day {
        cadence == .monthly ? latest.day.addingMonths(1) : latest.day.addingMonths(12)
    }

    public var id: String { "\(merchant.lowercased())|\(charges.map(\.id))" }
}

/// Something to be reminded of: a bill's due date, a warranty's end.
public struct UpcomingDate: Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case billDue, warrantyEnds
    }

    public var kind: Kind
    public var record: Record
    public var day: Day
    /// The amount due, when the record is a bill with a total.
    public var amount: Money?

    public var id: String { "\(kind.rawValue)-\(record.id.uuidString)-\(day.iso)" }
}

extension Day {
    /// The same day `months` later, or the month's last day if it's shorter.
    public func addingMonths(_ months: Int) -> Day {
        var month = self.month + months
        var year = self.year
        while month > 12 { month -= 12; year += 1 }
        while month < 1 { month += 12; year -= 1 }
        var day = self.day
        while day > 28, Day(year: year, month: month, day: day) == nil { day -= 1 }
        return Day(year: year, month: month, day: day) ?? Day(year: year, month: month, day: 28)!
    }
}

extension ArchiveStore {
    /// Every amount that can count as spending, with its record, duplicates
    /// already dropped as the person decided (or as guessed).
    func spendingAmounts() throws -> [Counted] {
        let all = try db.read { db -> [Counted] in
            let amounts = try Amount.filter(Column("kind") != AmountKind.payment.rawValue).fetchAll(db)
            let records = try Record.fetchAll(db, keys: Array(Set(amounts.map(\.recordId))))
            let byId = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            return amounts.compactMap { amount in byId[amount.recordId].map { Counted(transaction: amount, record: $0) } }
        }
        let dropped = Set(Self.duplicates(in: all, decisions: try duplicateDecisions()).map(\.dropped.id))
        return all.filter { !dropped.contains($0.id) }
    }

    /// Month by month, the latest `months` of them.
    public func spendingOverview(months limit: Int = 12) throws -> SpendingOverview {
        let all = try spendingAmounts()
        let currency = Dictionary(grouping: all, by: \.transaction.currency)
            .max { $0.value.count < $1.value.count }?.key ?? "USD"
        let items = all.filter { $0.transaction.currency == currency }
        guard let first = items.map(\.day).min(), let last = items.map(\.day).max() else {
            return SpendingOverview(currency: currency, months: [], otherCurrencyCount: all.count - items.count)
        }

        var months: [MonthSpending] = []
        var cursor = Day(year: first.year, month: first.month, day: 1)!
        while cursor <= last, let range = DayRange.month(cursor.month, of: cursor.year) {
            let inMonth = items.filter { range.contains($0.day) }
            var byCategory: [SpendCategory: Int64] = [:]
            for item in inMonth {
                byCategory[item.transaction.category, default: 0] += item.transaction.spendCents
            }
            months.append(MonthSpending(range: range, label: QuestionParser.monthLabel(cursor.month, cursor.year),
                                        totalCents: inMonth.reduce(0) { $0 + $1.transaction.spendCents },
                                        byCategory: byCategory, count: inMonth.count))
            cursor = cursor.addingMonths(1)
        }
        return SpendingOverview(currency: currency, months: Array(months.suffix(limit)),
                                otherCurrencyCount: all.count - items.count)
    }

    /// Charges that repeat monthly or yearly at a steady price, most
    /// expensive per year first. A merchant with other purchases in between
    /// (DoorDash orders around a DashPass fee) is split by exact amount.
    /// Ones not seen for two periods past the newest saved amount count as
    /// cancelled and are left out.
    public func recurringCharges() throws -> [RecurringCharge] {
        let items = try spendingAmounts().filter { [.purchase, .bill].contains($0.transaction.kind) }
        guard let newest = items.map(\.day).max() else { return [] }

        let byMerchant = Dictionary(grouping: items) { Self.merchantKey($0.transaction.merchant) }
        var found: [RecurringCharge] = []
        for (key, group) in byMerchant where !key.isEmpty {
            if let charge = Self.recurring(group) {
                found.append(charge)
            } else {
                for (_, sameAmount) in Dictionary(grouping: group, by: \.transaction.amountCents) {
                    if let charge = Self.recurring(sameAmount) { found.append(charge) }
                }
            }
        }
        return found
            .filter { charge in
                let periods = charge.cadence == .monthly ? 2 : 24
                return charge.latest.day.addingMonths(periods) >= newest
            }
            .sorted { ($0.yearlyCents, $0.merchant) > ($1.yearlyCents, $1.merchant) }
    }

    static func merchantKey(_ merchant: String) -> String {
        merchant.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Two or more charges, each a month (or a year) after the last, at
    /// close to the same price. Utilities may vary more.
    static func recurring(_ group: [Counted]) -> RecurringCharge? {
        let charges = group.sorted { ($0.day, $0.id) < ($1.day, $1.id) }
        guard charges.count >= 2, let first = charges.first else { return nil }
        let gaps = zip(charges, charges.dropFirst()).map { $0.day.days(to: $1.day) }
        let cadence: RecurringCharge.Cadence
        if gaps.allSatisfy({ (25...38).contains($0) }) {
            cadence = .monthly
        } else if gaps.allSatisfy({ (350...380).contains($0) }) {
            cadence = .yearly
        } else {
            return nil
        }
        let amounts = charges.map(\.transaction.amountCents)
        guard let low = amounts.min(), let high = amounts.max(), low > 0 else { return nil }
        let tolerance: Int64 = first.transaction.category == .utilities ? 200 : 125
        guard high * 100 <= low * tolerance else { return nil }
        guard Set(charges.map(\.transaction.currency)).count == 1 else { return nil }
        return RecurringCharge(merchant: charges[charges.count - 1].transaction.merchant,
                               category: charges[charges.count - 1].transaction.category,
                               cadence: cadence, charges: charges, currency: first.transaction.currency)
    }

    /// Bills and statements due, and warranties ending, on or after `today`,
    /// soonest first.
    public func upcomingDates(from today: Day) throws -> [UpcomingDate] {
        var dates: [UpcomingDate] = []
        let payable = try records().filter { ($0.kind == .bill || $0.kind == .statement) && $0.status == .ready }
        let totals = try recordTotals()
        try db.read { db in
            for record in payable {
                let rows = Extractor.rows(of: try Self.storedPages(of: record.id, in: db))
                if let due = Self.dueDate(in: rows), due >= today {
                    dates.append(UpcomingDate(kind: .billDue, record: record, day: due,
                                              amount: record.kind == .bill ? totals[record.id] : nil))
                }
            }
        }
        for finding in try expiries([]) where finding.day >= today {
            dates.append(UpcomingDate(kind: .warrantyEnds, record: finding.record, day: finding.day))
        }
        return dates.sorted { ($0.day, $0.record.title) < ($1.day, $1.record.title) }
    }

    /// The date on a "due" line: "DUE DATE 09/19/2026", "Payment Due By
    /// Aug 31, 2026". The first such line wins.
    static func dueDate(in rows: [TextRow]) -> Day? {
        for row in rows {
            let lower = row.text.lowercased()
            guard lower.contains("due"), !lower.contains("past due"), !lower.contains("overdue") else { continue }
            if let day = DayParser.firstDay(in: row.text) { return day }
        }
        return nil
    }
}

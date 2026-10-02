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
        /// The last day a purchase can be returned.
        case returnBy
        /// A passport, licence, registration, policy or lease runs out.
        case renewal
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
        // Things whose warranty end was typed in; linked warranties already
        // count above.
        for profile in try thingProfiles() where profile.thing.warrantyEnds != nil && profile.links(.warranty).isEmpty {
            if let end = profile.warrantyEnds, end >= today, let record = profile.links.first?.record {
                dates.append(UpcomingDate(kind: .warrantyEnds, record: record, day: end))
            }
        }
        for document in try importantDocuments() {
            if let expires = document.expires, expires >= today {
                dates.append(UpcomingDate(kind: .renewal, record: document.record, day: expires))
            }
        }
        // Receipts, and anything not yet filed that may be one.
        let receipts = try records().filter { [.receipt, .document, .other].contains($0.kind) && $0.status == .ready }
        try db.read { db in
            for record in receipts {
                let rows = Extractor.rows(of: try Self.storedPages(of: record.id, in: db))
                if let last = Self.returnDeadline(in: rows, purchased: record.documentDate), last >= today {
                    dates.append(UpcomingDate(kind: .returnBy, record: record, day: last, amount: totals[record.id]))
                }
            }
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

extension ArchiveStore {
    /// The last day to return a purchase, from its receipt's return policy:
    /// "RETURN BY 10/28/2026", "Returns accepted within 30 days",
    /// "90 day return policy". Days are counted from the purchase date.
    static func returnDeadline(in rows: [TextRow], purchased: Day?) -> Day? {
        let returnWords = ["return", "refund", "exchange"]
        // "All sales final unless defective": no window for changing your mind.
        if rows.contains(where: { $0.text.lowercased().contains("all sales final") }) { return nil }
        for row in rows {
            let lower = row.text.lowercased()
            guard returnWords.contains(where: { lower.contains($0) }), !lower.contains("defective") else { continue }
            if lower.contains(" by") || lower.contains("until") || lower.contains("before"),
               let day = DayParser.days(in: row.text).map(\.day).first(where: { $0 != purchased }) {
                return day
            }
            guard let purchased else { continue }
            let ns = row.text as NSString
            if let match = Self.returnDays.firstMatch(in: row.text, range: NSRange(location: 0, length: ns.length)) {
                let digits = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                if let count = Int(ns.substring(with: digits)), (1...365).contains(count) {
                    return purchased.adding(days: count)
                }
            }
        }
        return nil
    }

    /// "within 30 days", "30-day", "30 day", "30 days".
    static let returnDays = DayParser.regex("(?:within\\s+(\\d{1,3})\\s+days?)|(?:\\b(\\d{1,3})[\\s-]?days?\\b)")
}

// MARK: Budgets

/// A monthly limit for one category, or for all spending (`category` nil).
public struct Budget: Hashable, Sendable {
    public var category: SpendCategory?
    public var limitCents: Int64
}

/// How a budget is doing this month.
public struct BudgetStatus: Hashable, Identifiable, Sendable {
    public var budget: Budget
    public var spentCents: Int64
    public var currency: String

    public var fraction: Double { budget.limitCents > 0 ? Double(spentCents) / Double(budget.limitCents) : 0 }
    public var remainingCents: Int64 { budget.limitCents - spentCents }
    public var id: String { budget.category?.rawValue ?? "all" }
}

extension ArchiveStore {
    public func budgets() throws -> [Budget] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT category, limitCents FROM budget").map { row in
                let key: String = row["category"]
                return Budget(category: SpendCategory(rawValue: key), limitCents: row["limitCents"])
            }
            .sorted { ($0.category == nil ? 0 : 1, $0.category?.rawValue ?? "") < ($1.category == nil ? 0 : 1, $1.category?.rawValue ?? "") }
        }
    }

    /// Sets a monthly limit; nil or zero removes it.
    public func setBudget(_ limitCents: Int64?, for category: SpendCategory?) throws {
        let key = category?.rawValue ?? "all"
        try db.write { db in
            if let limitCents, limitCents > 0 {
                try db.execute(sql: """
                    INSERT INTO budget (category, limitCents) VALUES (?, ?)
                    ON CONFLICT(category) DO UPDATE SET limitCents = excluded.limitCents
                    """, arguments: [key, limitCents])
            } else {
                try db.execute(sql: "DELETE FROM budget WHERE category = ?", arguments: [key])
            }
        }
    }

    /// Each budget against what was spent in `month`, counted like answers.
    public func budgetStatus(in month: DayRange) throws -> [BudgetStatus] {
        let budgets = try budgets()
        guard !budgets.isEmpty else { return [] }
        let items = try spendingAmounts().filter { month.contains($0.day) }
        let currency = Dictionary(grouping: items, by: \.transaction.currency).max { $0.value.count < $1.value.count }?.key ?? "USD"
        return budgets.map { budget in
            let spent = items.filter { $0.transaction.currency == currency && (budget.category == nil || $0.transaction.category == budget.category) }
                .reduce(Int64(0)) { $0 + $1.transaction.spendCents }
            return BudgetStatus(budget: budget, spentCents: spent, currency: currency)
        }
    }
}

extension MonthSpending {
    /// Each budget against this month's spending, from the same totals the
    /// month shows, so its bars always agree with the number above them.
    public func budgetStatus(_ budgets: [Budget], currency: String) -> [BudgetStatus] {
        budgets.map { budget in
            BudgetStatus(budget: budget, spentCents: budget.category.map { byCategory[$0] ?? 0 } ?? totalCents, currency: currency)
        }
    }
}

// MARK: Serial numbers

extension ArchiveStore {
    /// "S/N: QN65Q80D-1234", "Serial No. 8XK2…", "Serial Number ABC123".
    static func serialNumber(in rows: [TextRow]) -> String? {
        let regex = DayParser.regex("(?:s/n|serial\\s*(?:no\\.?|number|#)?)\\s*[:#.]?\\s*([A-Z0-9][A-Z0-9-]{3,})")
        for row in rows {
            let ns = row.text as NSString
            if let match = regex.firstMatch(in: row.text, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: match.range(at: 1))
            }
        }
        return nil
    }
}
// MARK: Important documents

/// A passport, licence, registration, policy or lease, and when it runs out.
public struct ImportantDocument: Hashable, Identifiable, Sendable {
    public var record: Record
    public var expires: Day?
    /// The printed line the date came from.
    public var evidence: String?
    public var id: UUID { record.id }
}

extension ArchiveStore {
    /// Every ID and policy, soonest to expire first, ones without a date last.
    public func importantDocuments() throws -> [ImportantDocument] {
        let records = try records(kind: .identity)
        return try db.read { db in
            try records.map { record in
                let rows = Extractor.rows(of: try Self.storedPages(of: record.id, in: db))
                let printed = Self.printedExpiry(in: rows)
                return ImportantDocument(record: record, expires: printed?.day, evidence: printed?.row)
            }
        }
        .sorted { a, b in
            switch (a.expires, b.expires) {
            case let (x?, y?): x < y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.record.title < b.record.title
            }
        }
    }
}

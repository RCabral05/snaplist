import Foundation

/// Last month in one place: what it came to and how that compares, where it
/// went, the biggest purchases, what renewed, what changed price, and
/// anything counted once that's worth a look.
public struct MonthlyRecap: Sendable {
    public var month: MonthSpending
    public var previous: MonthSpending?
    public var currency: String
    /// Largest first, only categories with spending.
    public var categories: [(category: SpendCategory, cents: Int64)]
    /// The three biggest purchases, largest first.
    public var biggest: [Counted]
    /// Subscriptions and bills that charged this month.
    public var renewals: [Counted]
    public var priceChanges: [PriceChange]
    /// Pairs counted once on a guess, not yet confirmed.
    public var toReview: [Duplicate]

    public var deltaCents: Int64? { previous.map { month.totalCents - $0.totalCents } }
    public var renewalsCents: Int64 { renewals.reduce(0) { $0 + $1.transaction.spendCents } }
}

/// What a statement shows that the rest of the archive doesn't: charges with
/// no receipt, returns that never came back as credits, charges that just
/// started repeating, and subscriptions that changed price.
public struct StatementCheck: Sendable {
    public var period: DayRange
    /// Purchases with no saved receipt or bill, largest first.
    public var withoutReceipt: [Counted]
    /// Purchases matched to a saved receipt or bill.
    public var matched: Int
    /// Returns on saved receipts from the period with no credit on any statement.
    public var missingRefunds: [Counted]
    /// Charges that started repeating around this statement.
    public var newRecurring: [RecurringCharge]
    public var priceChanges: [PriceChange]

    public var isAllClear: Bool { missingRefunds.isEmpty && newRecurring.isEmpty && priceChanges.isEmpty }
}

extension ArchiveStore {
    /// The calendar month before `today`'s.
    public static func lastMonth(before today: Day) -> DayRange {
        let start = Day(year: today.year, month: today.month, day: 1)!.addingMonths(-1)
        return DayRange.month(start.month, of: start.year)!
    }

    /// Nil when nothing was spent that month.
    public func monthlyRecap(for range: DayRange) throws -> MonthlyRecap? {
        let overview = try spendingOverview(months: 120)
        guard let index = overview.months.firstIndex(where: { $0.range == range }), overview.months[index].count > 0 else { return nil }
        let month = overview.months[index]
        let inMonth = try spendingAmounts().filter { range.contains($0.day) && $0.transaction.currency == overview.currency }

        let recurring = try recurringCharges()
        let recurringIds = Set(recurring.flatMap { $0.charges.map(\.id) })
        let renewals = inMonth.filter { recurringIds.contains($0.id) }.sorted { $0.transaction.amountCents > $1.transaction.amountCents }
        let biggest = inMonth.filter { $0.transaction.kind == .purchase && !recurringIds.contains($0.id) }
            .sorted { ($0.transaction.amountCents, $0.id) > ($1.transaction.amountCents, $1.id) }

        return MonthlyRecap(
            month: month,
            previous: index > 0 ? overview.months[index - 1] : nil,
            currency: overview.currency,
            categories: month.byCategory.filter { $0.value > 0 }.sorted { ($0.value, $0.key.rawValue) > ($1.value, $1.key.rawValue) }
                .map { ($0.key, $0.value) },
            biggest: Array(biggest.prefix(3)),
            renewals: renewals,
            priceChanges: try priceChanges().filter { range.contains($0.latest.day) },
            toReview: try possibleDuplicates().filter { $0.decision == nil && range.contains($0.dropped.day) })
    }

    /// Nil for a record that isn't a statement or has no lines.
    public func statementCheck(_ recordId: UUID) throws -> StatementCheck? {
        guard let record = try record(recordId), record.kind == .statement else { return nil }
        let all = try everySpendingAmount()
        let lines = all.filter { $0.record.id == recordId }
        guard let first = lines.map(\.day).min(), let last = lines.map(\.day).max() else { return nil }
        let period = DayRange(first, last)

        let duplicates = Self.duplicates(in: all, decisions: try duplicateDecisions())
        let toReceipt = Set(duplicates.filter { $0.kept.transaction.source != .statement }.map(\.dropped.id))
        let purchases = lines.filter { $0.transaction.kind == .purchase || $0.transaction.kind == .fee }
        let withoutReceipt = purchases.filter { !toReceipt.contains($0.id) }
            .sorted { ($0.transaction.amountCents, $0.id) > ($1.transaction.amountCents, $1.id) }

        // A return made a week before the period may post on it.
        let credited = Set(duplicates.map(\.kept.id))
        let missingRefunds = all.filter { item in
            item.transaction.source == .receipt && item.transaction.kind == .refund && !credited.contains(item.id)
                && period.start.adding(days: -7) <= item.day && item.day <= period.end
        }

        let lineIds = Set(lines.map(\.id))
        let newRecurring = try recurringCharges().filter { charge in
            charge.charges.contains { lineIds.contains($0.id) } && charge.charges[0].day >= period.start.adding(days: -40)
        }
        let changes = try priceChanges().filter { lineIds.contains($0.latest.id) }

        return StatementCheck(period: period, withoutReceipt: withoutReceipt, matched: purchases.count - withoutReceipt.count,
                              missingRefunds: missingRefunds, newRecurring: newRecurring, priceChanges: changes)
    }
}

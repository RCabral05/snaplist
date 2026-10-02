import Foundation
import GRDB

/// A bill or subscription that costs something different from last time.
public struct PriceChange: Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable { case bill, subscription }

    public struct Line: Hashable, Sendable {
        public var name: String
        public var before: Int64?
        public var after: Int64?
        public var delta: Int64 { (after ?? 0) - (before ?? 0) }
    }

    public var kind: Kind
    public var merchant: String
    public var previous: Counted
    public var latest: Counted
    /// For bills that list their charges: what was added, removed or changed.
    public var lines: [Line]

    public var deltaCents: Int64 { latest.transaction.amountCents - previous.transaction.amountCents }
    public var percent: Int {
        let before = previous.transaction.amountCents
        guard before > 0 else { return 0 }
        return Int((Double(deltaCents) / Double(before) * 100).rounded())
    }
    public var currency: String { latest.transaction.currency }
    public var id: String { "\(kind.rawValue)-\(latest.id)" }
}

/// What one thing has cost over time: "What did I pay for eggs last time?",
/// "Cheapest place I've bought Tide?", "Has Costco chicken gone up?".
public struct PriceHistory: Sendable {
    public var terms: [String]
    /// Oldest first.
    public var points: [Counted]
    /// True when these are whole purchases (gas fill-ups), not receipt lines.
    public var isPurchases: Bool

    public var latest: Counted? { points.last }
    public var first: Counted? { points.first }
    public var lowest: Counted? { points.min { $0.transaction.amountCents < $1.transaction.amountCents } }
    public var highest: Counted? { points.max { $0.transaction.amountCents < $1.transaction.amountCents } }
    public var averageCents: Int64 {
        points.isEmpty ? 0 : points.reduce(0) { $0 + $1.transaction.amountCents } / Int64(points.count)
    }
    public var changeCents: Int64 {
        guard let first, let latest else { return 0 }
        return latest.transaction.amountCents - first.transaction.amountCents
    }
    public var currency: String { points.last?.transaction.currency ?? "USD" }
}

extension ArchiveStore {
    /// Each bill whose latest amount differs from the one before from the
    /// same company (by at least $1 and 3%), and each subscription whose
    /// latest charge differs from its previous one. Newest first.
    public func priceChanges() throws -> [PriceChange] {
        let amounts = try spendingAmounts()
        var changes: [PriceChange] = []

        let bills = amounts.filter { $0.transaction.source == .bill }
        for (_, group) in Dictionary(grouping: bills, by: { Self.merchantKey($0.transaction.merchant) }) where group.count >= 2 {
            let sorted = group.sorted { ($0.day, $0.id) < ($1.day, $1.id) }
            guard let (previous, latest) = Self.lastStep(in: sorted, steadyBefore: true) else { continue }
            changes.append(PriceChange(kind: .bill, merchant: latest.transaction.merchant, previous: previous, latest: latest,
                                       lines: try lineChanges(from: previous.record.id, to: latest.record.id)))
        }

        for charge in try recurringCharges() where charge.charges.count >= 2 && charge.latest.transaction.source != .bill {
            guard let (previous, latest) = Self.lastStep(in: charge.charges, steadyBefore: false) else { continue }
            changes.append(PriceChange(kind: .subscription, merchant: charge.merchant, previous: previous, latest: latest, lines: []))
        }
        return changes.sorted { ($0.latest.day, $0.id) > ($1.latest.day, $1.id) }
    }

    /// The most recent time the amount moved, if it was within the last
    /// three charges: a raise in August is still news in September, and
    /// still shown, but not a year later. With `steadyBefore`, only when the
    /// amount had held steady before it: an electric bill that changes with
    /// use every month hasn't had a price change.
    static func lastStep(in charges: [Counted], steadyBefore: Bool) -> (Counted, Counted)? {
        let amounts = charges.map(\.transaction.amountCents)
        guard let step = amounts.indices.dropFirst().last(where: { isMeaningful(amounts[$0 - 1], amounts[$0]) }),
              amounts.count - step <= 3 else { return nil }
        if steadyBefore {
            let before = amounts[..<step].suffix(3)
            guard before.allSatisfy({ !isMeaningful($0, amounts[step - 1]) }) else { return nil }
        }
        return (charges[step - 1], charges[step])
    }

    static func isMeaningful(_ before: Int64, _ after: Int64) -> Bool {
        let delta = abs(after - before)
        return delta >= 100 && before > 0 && delta * 100 >= before * 3
    }

    /// Lines on two bills compared by name: changed, added and removed, the
    /// biggest differences first. Empty when the bills don't list charges.
    func lineChanges(from before: UUID, to after: UUID) throws -> [PriceChange.Line] {
        let old = try items(of: before), new = try items(of: after)
        guard !old.isEmpty || !new.isEmpty else { return [] }
        func key(_ name: String) -> String { name.lowercased().filter { $0.isLetter } }
        var lines: [String: PriceChange.Line] = [:]
        for item in old { lines[key(item.name), default: .init(name: item.name)].before = item.amountCents }
        for item in new {
            lines[key(item.name), default: .init(name: item.name)].after = item.amountCents
            lines[key(item.name)]?.name = item.name
        }
        // Biggest first; at the same size, changed lines, then new ones, then
        // ones that went away, then by name.
        func order(_ line: PriceChange.Line) -> Int { line.before != nil && line.after != nil ? 0 : line.before == nil ? 1 : 2 }
        return lines.values.filter { $0.delta != 0 }.sorted {
            (-abs($0.delta), order($0), $0.name) < (-abs($1.delta), order($1), $1.name)
        }
    }

    /// What `terms` has cost: receipt lines naming it, or, for things bought
    /// whole like gas, purchases in `categories`. Nil when nothing matches.
    public func priceHistory(_ terms: [String], categories: Set<SpendCategory> = []) throws -> PriceHistory? {
        let items = try itemAmounts(matching: terms).sorted { ($0.day, $0.id) < ($1.day, $1.id) }
        if !items.isEmpty {
            return PriceHistory(terms: terms, points: items, isPurchases: false)
        }
        guard !categories.isEmpty else { return nil }
        let purchases = try spendingAmounts()
            .filter { categories.contains($0.transaction.category) && $0.transaction.kind == .purchase }
            .sorted { ($0.day, $0.id) < ($1.day, $1.id) }
        return purchases.isEmpty ? nil : PriceHistory(terms: terms, points: purchases, isPurchases: true)
    }
}

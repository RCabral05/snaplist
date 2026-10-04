import Foundation
import GRDB

/// A subscription as the Subscriptions screen shows it: one Snaplist found
/// repeating on statements, or a free trial typed in before it charges.
public struct Subscription: Hashable, Identifiable, Sendable {
    public var key: String
    public var name: String
    public var category: SpendCategory
    /// Nil for a trial that hasn't charged yet.
    public var charge: RecurringCharge?
    /// What it costs each time: the latest charge, or the price typed in.
    public var priceCents: Int64?
    public var currency: String
    public var cadence: RecurringCharge.Cadence
    public var trialEnds: Day?
    /// A notification two days before the next charge.
    public var remind: Bool
    public var cancelledOn: Day?

    public var id: String { key }
    public var isCancelled: Bool { cancelledOn != nil }
    /// Charged again after being marked cancelled.
    public var chargedAfterCancel: Bool {
        guard let cancelledOn, let latest = charge?.latest.day else { return false }
        return latest > cancelledOn
    }

    public var nextCharge: Day? {
        if isCancelled && !chargedAfterCancel { return nil }
        if let trialEnds, charge == nil || trialEnds > charge!.latest.day { return trialEnds }
        return charge?.nextExpected
    }

    public var monthlyCents: Int64 {
        guard let price = priceCents else { return 0 }
        return cadence == .monthly ? price : price / 12
    }

    public var yearlyCents: Int64 {
        guard let price = priceCents else { return 0 }
        return cadence == .monthly ? price * 12 : price
    }
}

/// What the person set for a subscription.
struct SubscriptionSetting: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "subscriptionSetting"
    var key: String
    var name: String
    var priceCents: Int64?
    var currency: String
    var cadence: String
    var trialEnds: Day?
    var remind: Bool
    var cancelledOn: Day?
}

extension ArchiveStore {
    /// Active ones first by next charge, then cancelled ones.
    public func subscriptions() throws -> [Subscription] {
        let settings = try db.read { try SubscriptionSetting.fetchAll($0) }
        let byKey = Dictionary(settings.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var list: [Subscription] = try recurringCharges().map { charge in
            let key = Self.merchantKey(charge.merchant)
            let setting = byKey[key]
            return Subscription(key: key, name: charge.merchant, category: charge.category, charge: charge,
                                priceCents: charge.typicalCents, currency: charge.currency, cadence: charge.cadence,
                                trialEnds: setting?.trialEnds, remind: setting?.remind ?? false, cancelledOn: setting?.cancelledOn)
        }
        let found = Set(list.map(\.key))
        // Trials typed in, until they show up on a statement.
        for setting in settings where setting.key.hasPrefix("trial:") && !found.contains(Self.merchantKey(setting.name)) {
            list.append(Subscription(key: setting.key, name: setting.name,
                                     category: SpendCategories.classify(merchant: setting.name, memo: ""),
                                     charge: nil, priceCents: setting.priceCents, currency: setting.currency,
                                     cadence: RecurringCharge.Cadence(rawValue: setting.cadence) ?? .monthly,
                                     trialEnds: setting.trialEnds, remind: setting.remind, cancelledOn: setting.cancelledOn))
        }
        return list.sorted { a, b in
            if a.isCancelled != b.isCancelled { return !a.isCancelled }
            return (a.nextCharge ?? Day(year: 9999, month: 1, day: 1)!, a.name) < (b.nextCharge ?? Day(year: 9999, month: 1, day: 1)!, b.name)
        }
    }

    /// Saves reminders, a trial's end, or being cancelled.
    public func save(_ subscription: Subscription) throws {
        // A trial for something already charging belongs to that subscription.
        let key = subscription.key.hasPrefix("trial:") ? subscription.key : Self.merchantKey(subscription.name)
        try db.write { db in
            try SubscriptionSetting(key: key, name: subscription.name, priceCents: subscription.priceCents,
                                    currency: subscription.currency, cadence: subscription.cadence.rawValue,
                                    trialEnds: subscription.trialEnds, remind: subscription.remind,
                                    cancelledOn: subscription.cancelledOn).save(db)
        }
    }

    /// A free trial that hasn't charged yet.
    public func addTrial(name: String, priceCents: Int64?, cadence: RecurringCharge.Cadence, ends: Day,
                         currency: String = "USD") throws {
        try db.write { db in
            try SubscriptionSetting(key: "trial:\(UUID().uuidString)", name: name, priceCents: priceCents, currency: currency,
                                    cadence: cadence.rawValue, trialEnds: ends, remind: true, cancelledOn: nil).save(db)
        }
    }

    public func deleteSubscriptionSetting(_ key: String) throws {
        try db.write { _ = try SubscriptionSetting.deleteOne($0, key: key) }
    }
}

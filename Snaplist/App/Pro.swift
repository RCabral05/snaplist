import Foundation
import StoreKit
import SwiftUI

/// What Snaplist Pro unlocks, so a locked screen can say what it would show.
enum ProFeature: String, Identifiable, CaseIterable {
    case records, spending, liveCharges, subscriptions, car, things, taxReport, privateShare, collections, themes, statementCheck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .records: "Unlimited records"
        case .spending: "Spending, budgets and recaps"
        case .liveCharges: "Live charges"
        case .subscriptions: "Subscriptions"
        case .car: "Car maintenance"
        case .things: "Things and claim packets"
        case .taxReport: "Tax report"
        case .privateShare: "Share with private details hidden"
        case .collections: "Unlimited collections"
        case .themes: "Every theme"
        case .statementCheck: "Statement check"
        }
    }

    var summary: String {
        switch self {
        case .records: "Free keeps up to \(Pro.freeRecordLimit) records. Pro has no limit."
        case .spending: "Month by month, by category, with budgets, a recap on the 1st and price-change alerts."
        case .liveCharges: "Apple Pay taps, banks and cards through SimpleFIN, and Apple Card, as they happen."
        case .subscriptions: "Everything that repeats, what it costs a year, and a heads-up before trials charge."
        case .car: "Service history from receipts and when the next oil change is due."
        case .things: "What you own, with its receipt, warranty and manual, ready for a claim."
        case .taxReport: "Records marked for taxes, by purpose, exported for your accountant."
        case .privateShare: "A copy with card numbers, addresses, names and phone numbers blacked out."
        case .collections: "Free has \(Pro.freeCollectionLimit) collections. Pro has as many as you like."
        case .themes: "Vault, Clarity and every theme to come."
        case .statementCheck: "Charges with no receipt, returns never credited, and new subscriptions on each statement."
        }
    }

    var symbol: String {
        switch self {
        case .records: "tray.full"
        case .spending: "chart.bar.xaxis"
        case .liveCharges: "creditcard"
        case .subscriptions: "repeat"
        case .car: "car"
        case .things: "sofa"
        case .taxReport: "building.columns"
        case .privateShare: "eye.slash"
        case .collections: "square.stack"
        case .themes: "paintpalette"
        case .statementCheck: "checkmark.seal"
        }
    }
}

/// Snaplist Pro through the App Store: a monthly or yearly subscription,
/// checked on the iPhone with StoreKit. Nothing about it goes through a
/// server of ours.
@MainActor
@Observable
final class Pro {
    static let shared = Pro()

    static let freeRecordLimit = 25
    static let freeCollectionLimit = 2
    static let monthlyID = "com.rcabral.snaplist.pro.monthly"
    static let yearlyID = "com.rcabral.snaplist.pro.yearly"
    /// Apple's standard terms, which App Review asks subscription apps to link.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// Set before release: App Review needs a privacy policy linked from the paywall.
    static let privacyURL: URL? = nil
    static let testOverrideKey = "proTestOverride"

    /// Yearly first.
    private(set) var products: [Product] = []
    private(set) var hasSubscription = false
    /// TestFlight or Xcode: a switch in Settings can turn Pro on and off.
    private(set) var isTestBuild = false
    var testOverride: Bool? {
        didSet { UserDefaults.standard.set(testOverride, forKey: Self.testOverrideKey) }
    }
    /// What the paywall is shown for, when it's up.
    var paywall: ProFeature?

    private var updates: Task<Void, Never>?

    private init() {
        testOverride = UserDefaults.standard.object(forKey: Self.testOverrideKey) as? Bool
        #if DEBUG
        isTestBuild = true
        #endif
    }

    var isUnlocked: Bool {
        #if DEBUG
        // Screenshots and the simulator see everything unless switched off.
        return testOverride ?? true
        #else
        if isTestBuild, let testOverride { return testOverride }
        return hasSubscription
        #endif
    }

    /// True when `feature` can be used; otherwise puts up the paywall.
    @discardableResult
    func require(_ feature: ProFeature) -> Bool {
        if isUnlocked { return true }
        paywall = feature
        return false
    }

    func start() async {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refresh()
            }
        }
        if let app = try? await AppTransaction.shared, case .verified(let transaction) = app {
            isTestBuild = isTestBuild || transaction.environment != .production
        }
        products = ((try? await Product.products(for: [Self.yearlyID, Self.monthlyID])) ?? [])
            .sorted { $0.id == Self.yearlyID && $1.id != Self.yearlyID }
        await refresh()
    }

    func refresh() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement, [Self.monthlyID, Self.yearlyID].contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        hasSubscription = active
    }

    /// True when it went through.
    func purchase(_ product: Product) async throws -> Bool {
        switch try await product.purchase() {
        case .success(let result):
            if case .verified(let transaction) = result {
                await transaction.finish()
                await refresh()
                return true
            }
            return false
        case .pending, .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }
}

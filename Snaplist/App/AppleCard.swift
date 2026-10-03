import ArchiveCore
import Foundation
#if canImport(FinanceKit)
import FinanceKit
#endif

/// Apple Card, Apple Cash and Savings transactions, read from Wallet on this
/// iPhone through FinanceKit: nothing goes through a server. Needs Apple to
/// grant Snaplist the FinanceKit entitlement; until then connecting says so.
enum AppleCard {
    static let enabledKey = "appleCardEnabled"
    static let lastSyncKey = "appleCardLastSync"

    enum Failure: LocalizedError {
        case unavailable, notAllowed, notApproved(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "Apple Card data isn't available on this iPhone."
            case .notAllowed: "Snaplist wasn't given access. You can allow it in the Settings app under Privacy & Security, Wallet."
            case .notApproved(let detail): "Apple hasn't switched on Apple Card access for Snaplist yet. (\(detail))"
            }
        }
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var lastSync: Date? {
        let value = UserDefaults.standard.double(forKey: lastSyncKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    /// Asks for access; true when granted.
    static func connect() async throws {
        #if canImport(FinanceKit)
        guard FinanceStore.isDataAvailable(.financialData) else { throw Failure.unavailable }
        let status: AuthorizationStatus
        do {
            status = try await FinanceStore.shared.requestAuthorization()
        } catch {
            throw Failure.notApproved(error.localizedDescription)
        }
        guard status == .authorized else { throw Failure.notAllowed }
        UserDefaults.standard.set(true, forKey: enabledKey)
        #else
        throw Failure.unavailable
        #endif
    }

    static func disconnect() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
    }

    /// Booked transactions since `start`, by account. Pending ones wait until
    /// they're booked, since their amounts can still change.
    static func charges(since start: Date) async throws -> [(feed: String, charges: [LiveCharge])] {
        #if canImport(FinanceKit)
        let store = FinanceStore.shared
        let accounts = try await store.accounts(query: AccountQuery())
        let names = Dictionary(accounts.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let transactions = try await store.transactions(query: TransactionQuery(
            sortDescriptors: [SortDescriptor(\Transaction.transactionDate)],
            predicate: #Predicate<Transaction> { $0.transactionDate >= start }))
        var byAccount: [String: [LiveCharge]] = [:]
        for transaction in transactions where transaction.status == .booked {
            let cents = NSDecimalNumber(decimal: transaction.transactionAmount.amount * 100).int64Value
            guard cents != 0 else { continue }
            let description = transaction.transactionDescription
            let text = description.lowercased()
            let out = transaction.creditDebitIndicator == .debit
            let isPayment = out ? CSVStatement.isMovedOut(text) : CSVStatement.isMoneyIn(text)
            let charge = LiveCharge(id: transaction.id.uuidString, day: Day(transaction.transactionDate),
                                    description: description, merchant: transaction.merchantName ?? "",
                                    amountCents: out ? abs(cents) : -abs(cents),
                                    currency: transaction.transactionAmount.currencyCode, isPayment: isPayment)
            byAccount[names[transaction.accountID] ?? "Apple Card", default: []].append(charge)
        }
        return byAccount.map { ($0.key, $0.value) }.sorted { $0.feed < $1.feed }
        #else
        return []
        #endif
    }
}

extension AppModel {
    /// New Apple Card charges. The first sync goes back 90 days; later ones
    /// overlap the last by a week.
    @discardableResult
    func syncAppleCard() async throws -> Int {
        let start = AppleCard.lastSync.map { $0.addingTimeInterval(-7 * 86_400) } ?? Date.now.addingTimeInterval(-90 * 86_400)
        var added = 0
        for (feed, charges) in try await AppleCard.charges(since: start) where !charges.isEmpty {
            added += try archive.addLive(charges, feed: feed, source: .wallet)
        }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: AppleCard.lastSyncKey)
        if added > 0 { amountsChanged() }
        return added
    }
}

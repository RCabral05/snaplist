import Foundation
import GRDB

/// A charge that didn't come from a document: an Apple Pay tap logged by a
/// Shortcuts automation, or a transaction from a connected bank.
public struct LiveCharge: Hashable, Sendable {
    /// The bank's own id, so syncing again never adds it twice. Nil for taps.
    public var id: String?
    public var day: Day
    /// As the bank printed it, or the merchant for a tap.
    public var description: String
    /// The merchant's name when the source gives one.
    public var merchant: String
    /// Money out is positive; money back is negative.
    public var amountCents: Int64
    public var currency: String
    /// Paying off the card, a paycheck, a transfer: not spending either way.
    public var isPayment: Bool

    public init(id: String? = nil, day: Day, description: String, merchant: String = "", amountCents: Int64,
                currency: String = "USD", isPayment: Bool = false) {
        self.id = id
        self.day = day
        self.description = description
        self.merchant = merchant
        self.amountCents = amountCents
        self.currency = currency
        self.isPayment = isPayment
    }
}

extension Archive {
    /// Adds charges to a statement per card per month ("Apple Card ·
    /// October 2026"), kept as a CSV original that grows as charges come in.
    /// Being statements, they're counted once against receipts and against a
    /// statement imported later. Returns how many were new.
    @discardableResult
    public func addLive(_ charges: [LiveCharge], feed: String) throws -> Int {
        var added = 0
        let byMonth = Dictionary(grouping: charges) { $0.day.year * 100 + $0.day.month }
        for (month, charges) in byMonth.sorted(by: { $0.key < $1.key }) {
            let key = "\(feed)|\(month)"
            var rows: [String]
            let record: Record
            if let existing = try liveRecord(key), let asset = try store.assets(of: existing.id).first {
                record = existing
                rows = (try? String(contentsOf: url(for: asset), encoding: .utf8))?
                    .split(whereSeparator: \.isNewline).map(String.init) ?? [LiveCSV.header]
                if rows.first != LiveCSV.header { rows.insert(LiveCSV.header, at: 0) }
                let known = Set(rows.dropFirst().compactMap { CSVStatement.fields($0).last }.filter { !$0.isEmpty })
                let new = charges.filter { $0.id == nil || !known.contains($0.id!) }
                guard !new.isEmpty else { continue }
                rows += Self.inDayOrder(new).map(LiveCSV.row)
                added += new.count
                let data = Data((rows.joined(separator: "\n") + "\n").utf8)
                try data.write(to: url(for: asset), options: .atomic)
                try store.updateSize(of: asset.id, to: Int64(data.count))
            } else {
                var seen = Set<String>()
                let unique = charges.filter { $0.id.map { seen.insert($0).inserted } ?? true }
                rows = [LiveCSV.header] + Self.inDayOrder(unique).map(LiveCSV.row)
                added += unique.count
                let label = QuestionParser.monthLabel(month % 100, month / 100)
                record = try add(kind: .statement, title: "\(feed) · \(label)", nameSource: .file,
                                 items: [ImportItem(type: .csv, source: .data(Data((rows.joined(separator: "\n") + "\n").utf8)),
                                                    fileExtension: "csv")])
                try store.setLiveRecord(record.id, key: key)
            }
            guard let asset = try store.assets(of: record.id).first else { continue }
            let page = RecognizedPage(lines: rows.map { RecognizedLine(text: $0) }, source: .file)
            try store.saveText([ExtractedAsset(assetId: asset.id, pages: [page])], for: record.id)
            try store.addMissingLines(of: page, to: record.id)
        }
        return added
    }

    /// By day, keeping the order they came in within a day.
    private static func inDayOrder(_ charges: [LiveCharge]) -> [LiveCharge] {
        charges.enumerated().sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }.map(\.element)
    }

    private func liveRecord(_ key: String) throws -> Record? {
        guard let id = try store.liveRecordId(key) else { return nil }
        return try store.record(id)
    }
}

extension ArchiveStore {
    func liveRecordId(_ key: String) throws -> UUID? {
        try db.read { try UUID.fetchOne($0, sql: "SELECT recordId FROM liveFeed WHERE key = ?", arguments: [key]) }
    }

    func setLiveRecord(_ recordId: UUID, key: String) throws {
        try db.write {
            try $0.execute(sql: "INSERT OR REPLACE INTO liveFeed (key, recordId) VALUES (?, ?)", arguments: [key, recordId])
        }
    }

    func updateSize(of assetId: UUID, to size: Int64) throws {
        try db.write { try $0.execute(sql: "UPDATE asset SET byteSize = ? WHERE id = ?", arguments: [size, assetId]) }
    }

    /// Re-reading leaves a statement alone once a line on it was corrected,
    /// so new charges on a live statement are added on their own.
    func addMissingLines(of page: RecognizedPage, to recordId: UUID) throws {
        let facts = CSVStatement.statement(page, recordId: recordId)
        try db.write { db in
            let have = Set(try Int.fetchAll(db, sql: "SELECT linePosition FROM txn WHERE recordId = ? AND linePosition IS NOT NULL",
                                            arguments: [recordId]))
            for var line in facts.transactions where !have.contains(line.linePosition ?? -1) {
                line.category = try Self.category(merchant: line.merchant, memo: line.memo, in: db)
                try line.insert(db)
            }
        }
    }
}

/// The CSV a live statement keeps: one row per charge, in the columns the
/// CSV reader already knows.
enum LiveCSV {
    static let header = "Date,Description,Merchant,Type,Amount,ID"

    static func row(_ charge: LiveCharge) -> String {
        let type = charge.isPayment ? "Payment" : charge.amountCents >= 0 ? "Purchase" : "Return"
        // Purchases positive; payments and returns negative.
        let cents = charge.isPayment ? -abs(charge.amountCents) : charge.amountCents
        let amount = (cents < 0 ? "-" : "") + String(format: "%d.%02d", abs(cents) / 100, abs(cents) % 100)
        return [charge.day.iso, charge.description, charge.merchant, type, amount, charge.id ?? ""].map(quoted).joined(separator: ",")
    }

    static func quoted(_ field: String) -> String {
        guard field.contains(where: { ",\"\n".contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: Apple Pay taps

extension LiveCharge {
    /// What a Shortcuts Wallet automation hands over: the merchant and the
    /// amount as text ("$4.50", "4,50 €"). Nil when the amount can't be read.
    public static func tap(merchant: String, amount: String, on day: Day) -> LiveCharge? {
        let parsed = MoneyParser.amounts(in: amount).last
        guard let cents = parsed.map({ $0.isCredit ? -$0.cents : $0.cents }) ?? CSVStatement.cents(amount), cents != 0 else {
            return nil
        }
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return LiveCharge(day: day, description: name.isEmpty ? "Apple Pay" : name, merchant: name, amountCents: cents,
                          currency: parsed?.currency ?? "USD")
    }
}

// MARK: SimpleFIN

/// What a SimpleFIN Bridge server returns for `/accounts`.
public struct SimpleFINResponse: Decodable, Sendable {
    public struct Organization: Decodable, Sendable {
        public var name: String?
        public var domain: String?
    }

    public struct Transaction: Decodable, Sendable {
        public var id: String
        public var posted: Int
        public var amount: String
        public var description: String
        public var payee: String?
        public var pending: Bool?
    }

    public struct Account: Decodable, Sendable {
        public var org: Organization?
        public var id: String
        public var name: String
        public var currency: String?
        public var transactions: [Transaction]?
    }

    public var errors: [String]
    public var accounts: [Account]

    enum CodingKeys: String, CodingKey { case errors, accounts }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errors = try container.decodeIfPresent([String].self, forKey: .errors) ?? []
        accounts = try container.decodeIfPresent([Account].self, forKey: .accounts) ?? []
    }

    /// Each account's posted transactions as charges, under a name for the
    /// account: "Chase Sapphire Preferred". Pending ones wait until they post,
    /// since their amounts can still change.
    public func charges() -> [(feed: String, charges: [LiveCharge])] {
        accounts.map { account in
            let org = account.org?.name?.trimmingCharacters(in: .whitespaces) ?? ""
            let feed = org.isEmpty || account.name.lowercased().contains(org.lowercased()) ? account.name : "\(org) \(account.name)"
            let isBankAccount = ["checking", "savings", "chequing"].contains { account.name.lowercased().contains($0) }
            let charges = (account.transactions ?? []).compactMap { transaction -> LiveCharge? in
                guard transaction.pending != true, let signed = CSVStatement.cents(transaction.amount), signed != 0 else { return nil }
                // SimpleFIN signs money leaving the account negative.
                let out = signed < 0
                let text = "\(transaction.description) \(transaction.payee ?? "")".lowercased()
                let isPayment = out ? CSVStatement.movedOut.contains { text.contains($0) }
                    : (isBankAccount && !["refund", "return", "reversal"].contains { text.contains($0) })
                        || CSVStatement.moneyIn.contains { text.contains($0) }
                return LiveCharge(id: transaction.id, day: Day(Date(timeIntervalSince1970: TimeInterval(transaction.posted))),
                                  description: transaction.description, merchant: transaction.payee ?? "",
                                  amountCents: -signed, currency: account.currency ?? "USD", isPayment: isPayment)
            }
            return (feed, charges)
        }
    }

    /// A setup token is the claim URL, base64-encoded.
    public static func claimURL(fromSetupToken token: String) -> URL? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        var base64 = trimmed
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64), let text = String(data: data, encoding: .utf8),
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https" else { return nil }
        return url
    }
}

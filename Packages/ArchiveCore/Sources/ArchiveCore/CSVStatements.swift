import Foundation

/// Transactions from a bank's or card's own export, such as Apple Card's
/// "Export Transactions" CSV. Exact, unlike reading a PDF: every column is
/// labelled. The file's lines are stored as one page, one line each, so an
/// amount still points back at the line it came from.
enum CSVStatement {
    /// Splits one CSV line into fields, honouring quotes ("a, b" and "").
    static func fields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        var iterator = line.makeIterator()
        var pending: Character? = nil
        while let character = pending ?? iterator.next() {
            pending = nil
            switch character {
            case "\"" where quoted:
                if let next = iterator.next() {
                    if next == "\"" { current.append("\"") } else { quoted = false; pending = next }
                } else {
                    quoted = false
                }
            case "\"" where current.isEmpty:
                quoted = true
            case "," where !quoted:
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default:
                current.append(character)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    struct Columns {
        var date: Int
        var description: Int?
        var merchant: Int?
        var category: Int?
        var type: Int?
        var amount: Int?
        var debit: Int?
        var credit: Int?
    }

    /// Which column is which, from the header row. Nil when it isn't a
    /// transactions file (no date, or nothing that holds an amount).
    static func columns(_ header: [String]) -> Columns? {
        let names = header.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF} ")) }
        func first(_ candidates: [String], contains: Bool = false) -> Int? {
            for candidate in candidates {
                if let index = names.firstIndex(where: { contains ? $0.contains(candidate) : $0 == candidate }) { return index }
            }
            return nil
        }
        guard let date = first(["transaction date", "date", "posted date", "posting date", "trans. date", "trans date"])
                ?? first(["date"], contains: true) else { return nil }
        let columns = Columns(
            date: date,
            description: first(["description", "name", "payee", "details", "memo"]),
            merchant: first(["merchant", "merchant name"]),
            category: first(["category"]),
            type: first(["type", "transaction type"]),
            amount: first(["amount"], contains: true),
            debit: first(["debit", "withdrawal", "withdrawals"], contains: true),
            credit: first(["credit", "deposit", "deposits"], contains: true))
        guard columns.amount != nil || columns.debit != nil else { return nil }
        guard columns.description != nil || columns.merchant != nil else { return nil }
        return columns
    }

    static func looksLikeCSV(_ pages: [RecognizedPage]) -> Bool {
        guard let page = pages.first, page.source == .file, let header = page.lines.first?.text else { return false }
        return columns(fields(header)) != nil
    }

    /// Every transaction row as an amount. Purchases come out positive
    /// whichever sign convention the bank uses.
    static func statement(_ page: RecognizedPage, recordId: UUID) -> ExtractedFacts {
        guard let header = page.lines.first?.text, let columns = columns(fields(header)) else { return ExtractedFacts() }

        struct Row {
            var line: Int
            var date: Day
            var description: String
            var merchant: String
            var category: String
            var type: String
            var cents: Int64
        }
        var rows: [Row] = []
        for (index, line) in page.lines.enumerated().dropFirst() {
            let cells = fields(line.text)
            func cell(_ column: Int?) -> String {
                guard let column, column < cells.count else { return "" }
                return cells[column]
            }
            guard let date = DayParser.firstDay(in: cell(columns.date)) else { continue }
            // One signed amount column, or money out and money in in two
            // (out comes out negative, as most banks print it).
            let value: Int64
            if let amount = Self.cents(cell(columns.amount)) {
                value = amount
            } else if let debit = Self.cents(cell(columns.debit)), debit != 0 {
                value = -abs(debit)
            } else if let credit = Self.cents(cell(columns.credit)) {
                value = abs(credit)
            } else {
                continue
            }
            rows.append(Row(line: index, date: date, description: cell(columns.description), merchant: cell(columns.merchant),
                            category: cell(columns.category), type: cell(columns.type), cents: value))
        }

        // Most banks show purchases as negative; Apple Card shows them
        // positive. Whichever sign most purchase-typed (or most) rows have is
        // the purchase sign.
        let purchases = rows.filter { $0.type.lowercased().contains("purchase") }
        let sample = purchases.isEmpty ? rows : purchases
        // Debit and credit columns leave no doubt: money out was made negative.
        let purchasesNegative = columns.amount == nil || sample.count(where: { $0.cents < 0 }) > sample.count / 2

        var transactions: [Amount] = []
        for row in rows where row.cents != 0 {
            let out = purchasesNegative ? row.cents < 0 : row.cents > 0
            let type = row.type.lowercased()
            let text = "\(row.description) \(row.merchant)".lowercased()
            let kind: AmountKind
            if type.contains("payment") || (!out && ["payment", "autopay", "thank you", "transfer from", "ach deposit"].contains { text.contains($0) }) {
                kind = .payment
            } else if type.contains("interest") || type.contains("fee") {
                kind = .fee
            } else if out {
                kind = .purchase
            } else {
                kind = .refund
            }
            // The bank's own merchant name, as written if it has its own
            // capitals ("DoorDash"), tidied if it's all capitals.
            let merchant = row.merchant.isEmpty ? Extractor.merchantName(row.description)
                : row.merchant == row.merchant.uppercased() ? Suggester.titleCased(row.merchant) : row.merchant
            let category = kind == .payment ? SpendCategory.other : bankCategory(row.category)
            transactions.append(Amount(
                recordId: recordId, pagePosition: 0, linePosition: row.line, date: row.date,
                merchant: merchant, memo: row.description.isEmpty ? row.merchant : row.description,
                amountCents: abs(row.cents), currency: "USD", kind: kind, category: category, source: .statement))
        }
        return ExtractedFacts(documentDate: rows.map(\.date).max(), transactions: transactions)
    }

    /// "-1,234.56", "$12.00", "(5.00)" → signed cents.
    static func cents(_ text: String) -> Int64? {
        var value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        var negative = false
        if value.hasPrefix("("), value.hasSuffix(")") { negative = true; value = String(value.dropFirst().dropLast()) }
        if value.hasPrefix("-") { negative = true; value.removeFirst() }
        value = value.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("-") { negative = true; value.removeFirst() }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = Int64(parts[0].isEmpty ? "0" : String(parts[0])) else { return nil }
        var fraction: Int64 = 0
        if parts.count == 2 {
            var digits = String(parts[1].prefix(2))
            while digits.count < 2 { digits += "0" }
            guard let parsed = Int64(digits) else { return nil }
            fraction = parsed
        }
        let cents = whole * 100 + fraction
        return negative ? -cents : cents
    }

    /// The bank's own category, when it says one, else nil so the word lists
    /// decide. Apple Card's names, and common ones elsewhere.
    static func bankCategory(_ name: String) -> SpendCategory? {
        let lower = name.lowercased()
        let map: [(String, SpendCategory)] = [
            ("restaurant", .dining), ("food & drink", .dining), ("dining", .dining),
            ("gas", .fuel), ("fuel", .fuel),
            ("grocer", .groceries), ("supermarket", .groceries),
            ("health", .pharmacy), ("medical", .pharmacy), ("pharmacy", .pharmacy),
            ("utilities", .utilities), ("bills", .utilities),
            ("shopping", .shopping), ("merchandise", .shopping),
            ("transportation", .travel), ("travel", .travel), ("airline", .travel), ("hotel", .travel),
        ]
        return map.first { lower.contains($0.0) }?.1
    }
}

import Foundation

/// A row of text as printed: OCR often returns "TOTAL" and "72.65" as two
/// observations on the same line, which only mean something together.
struct TextRow: Equatable {
    var text: String
    var pagePosition: Int
    /// The first line in the row, for pointing back at it.
    var linePosition: Int
}

/// What's read from a record's text, beyond its name.
struct ExtractedFacts: Equatable {
    var documentDate: Day?
    var transactions: [Amount] = []
    /// A receipt's lines: "ORGANIC EGGS 24  8.79".
    var items: [LineItem] = []
}

/// Reads dates and amounts from receipts, bills and statements with plain
/// rules. It prefers missing a value to inventing one: a receipt with no
/// recognisable total gets no amount, and the person can type it in.
enum Extractor {
    static func extract(kind: RecordKind, pages: [RecognizedPage], recordId: UUID, merchant: String) -> ExtractedFacts {
        // A bank's own export: its columns say what everything is.
        if CSVStatement.looksLikeCSV(pages), let page = pages.first {
            return CSVStatement.statement(page, recordId: recordId)
        }
        let rows = rows(of: pages)
        switch kind {
        case .receipt: return receipt(rows, recordId: recordId, merchant: merchant)
        case .bill: return bill(rows, recordId: recordId, merchant: merchant)
        case .statement: return statement(rows, recordId: recordId)
        case .identity:
            // Not the first date: on IDs that's often a date of birth.
            return ExtractedFacts(documentDate: labelledDate(in: rows, labels: ["date of issue", "issue date", "issued", "iss "]))
        case .warranty, .manual, .document, .item, .other:
            return ExtractedFacts(documentDate: rows.lazy.compactMap { DayParser.firstDay(in: $0.text) }.first)
        }
    }

    // MARK: Rows

    static func rows(of pages: [RecognizedPage]) -> [TextRow] {
        pages.enumerated().flatMap { pagePosition, page in rows(of: page, pagePosition: pagePosition) }
    }

    /// Joins lines whose boxes share most of their height into one row, left
    /// to right, and puts rows in reading order. The lines can come in any
    /// order: a PDF often stores a table column by column (every date, then
    /// every description, then every amount), which only reads as rows once
    /// it's put back together by position. Lines without boxes are rows
    /// already, in the order given.
    static func rows(of page: RecognizedPage, pagePosition: Int) -> [TextRow] {
        struct Row {
            var fragments: [(x: Double, text: String)]
            var line: Int
            var midY: Double
            var height: Double
        }
        var rows: [Row] = []
        for (index, line) in page.lines.enumerated() {
            guard let box = line.box else {
                rows.append(Row(fragments: [(0, line.text)], line: index, midY: Double(index), height: 0))
                continue
            }
            let midY = box.y + box.height / 2
            // Same row when the two overlap for at least half the shorter
            // one's height: a date cell and an amount cell rarely match exactly.
            if let match = rows.firstIndex(where: { row in
                guard row.height > 0 else { return false }
                let overlap = min(row.midY + row.height / 2, box.y + box.height) - max(row.midY - row.height / 2, box.y)
                return overlap >= min(row.height, box.height) * 0.5
            }) {
                rows[match].fragments.append((box.x, line.text))
                rows[match].height = max(rows[match].height, box.height)
                rows[match].line = min(rows[match].line, index)
            } else {
                rows.append(Row(fragments: [(box.x, line.text)], line: index, midY: midY, height: box.height))
            }
        }
        if rows.allSatisfy({ $0.height > 0 }) {
            rows.sort { $0.midY < $1.midY }
        }
        return rows.map { row in
            let text = row.fragments.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")
            return TextRow(text: text, pagePosition: pagePosition, linePosition: row.line)
        }
    }

    // MARK: Receipts and bills

    /// Highest priority first. Rows mentioning any of `notTotal` are skipped.
    static let receiptTotals = ["grand total", "total due", "amount due", "balance due", "total amount",
                                "fuel total", "sale total", "order total", "total", "amount"]
    static let billTotals = ["total amount due", "amount due", "total due", "balance due", "new balance",
                             "total current charges", "total"]
    static let notTotal = ["subtotal", "sub total", "sub-total", "total savings", "you saved", "total items",
                           "items sold", "total qty", "tax total", "total tax", "points", "previous balance"]

    static func receipt(_ rows: [TextRow], recordId: UUID, merchant: String) -> ExtractedFacts {
        let date = firstDate(in: rows, avoiding: ["exp", "valid", "return by", "due"])
        guard let (amount, row) = labelledAmount(in: rows, labels: receiptTotals) else {
            return ExtractedFacts(documentDate: date)
        }
        let transaction = Amount(
            recordId: recordId, pagePosition: row.pagePosition, linePosition: row.linePosition, date: date,
            merchant: merchant, memo: row.text, amountCents: amount.cents, currency: amount.currency ?? "USD",
            kind: amount.isCredit ? .refund : .purchase, source: .receipt)
        return ExtractedFacts(documentDate: date, transactions: [transaction],
                              items: lineItems(rows, recordId: recordId, before: row, totalCents: amount.cents))
    }

    /// Words on a receipt's rows that aren't things bought.
    static let notItem = ["total", "subtotal", "sub total", "tax", "change", "cash", "tend", "visa", "mastercard",
                          "amex", "discover", "debit", "credit", "card", "balance", "payment", "due", "auth",
                          "approv", "saving", "saved", "discount", "coupon", "points", "reward", "tip", "gratuity",
                          "deposit", "refund", "price/", "/gal", "per gal", "items sold", "qty", "thank", "store #",
                          "member", "acct", "account", "ref #", "trn", "reg#"]

    /// "OLIVE OIL 2L" → "Olive Oil 2L"; short codes like "AA" and "KS" stay.
    static func itemName(_ text: String) -> String {
        guard text == text.uppercased() else { return text }
        return text.split(separator: " ").map { word in
            word.count(where: \.isLetter) <= 2 || word.contains(where: \.isNumber) ? String(word) : word.capitalized
        }.joined(separator: " ")
    }

    /// Rows above the total that end in an amount and name something.
    static func lineItems(_ rows: [TextRow], recordId: UUID, before total: TextRow, totalCents: Int64) -> [LineItem] {
        var items: [LineItem] = []
        for row in rows {
            if (row.pagePosition, row.linePosition) >= (total.pagePosition, total.linePosition) { break }
            let lower = row.text.lowercased()
            guard !notItem.contains(where: { lower.contains($0) }), DayParser.firstDay(in: row.text) == nil,
                  let amount = MoneyParser.amounts(in: row.text).last, !amount.isCredit,
                  amount.cents > 0, amount.cents <= totalCents else { continue }
            let ns = row.text as NSString
            // Only a tax flag ("T", "N F") may follow the price.
            let after = ns.substring(from: amount.range.location + amount.range.length).trimmingCharacters(in: .whitespaces)
            guard after.count <= 3 else { continue }
            let name = ns.substring(to: amount.range.location)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "$*#:-")))
            guard name.count(where: \.isLetter) >= 3 else { continue }
            items.append(LineItem(recordId: recordId, pagePosition: row.pagePosition, linePosition: row.linePosition,
                                  name: itemName(name), amountCents: amount.cents,
                                  currency: amount.currency ?? "USD"))
        }
        return items
    }

    static func bill(_ rows: [TextRow], recordId: UUID, merchant: String) -> ExtractedFacts {
        let date = labelledDate(in: rows, labels: ["statement date", "bill date", "invoice date", "date issued"])
            ?? firstDate(in: rows, avoiding: ["due"])
        guard let (amount, row) = labelledAmount(in: rows, labels: billTotals), !amount.isCredit else {
            return ExtractedFacts(documentDate: date)
        }
        let transaction = Amount(
            recordId: recordId, pagePosition: row.pagePosition, linePosition: row.linePosition, date: date,
            merchant: merchant, memo: row.text, amountCents: amount.cents, currency: amount.currency ?? "USD",
            kind: .bill, category: SpendCategories.classify(merchant: merchant, memo: "utility"), source: .bill)
        return ExtractedFacts(documentDate: date, transactions: [transaction])
    }

    /// The amount on the row with the best label, or on the row after it when
    /// OCR split the label and the number onto separate lines.
    static func labelledAmount(in rows: [TextRow], labels: [String]) -> (ParsedAmount, TextRow)? {
        for label in labels {
            for (index, row) in rows.enumerated() {
                let lower = row.text.lowercased()
                guard lower.contains(label), !notTotal.contains(where: { lower.contains($0) }) else { continue }
                if let amount = MoneyParser.amounts(in: row.text).last {
                    return (amount, row)
                }
                if index + 1 < rows.count, MoneyParser.amounts(in: rows[index + 1].text).count == 1,
                   let amount = MoneyParser.amounts(in: rows[index + 1].text).first {
                    return (amount, rows[index + 1])
                }
            }
        }
        return nil
    }

    static func labelledDate(in rows: [TextRow], labels: [String]) -> Day? {
        for row in rows {
            let lower = row.text.lowercased()
            if labels.contains(where: { lower.contains($0) }), let day = DayParser.firstDay(in: row.text) {
                return day
            }
        }
        return nil
    }

    static func firstDate(in rows: [TextRow], avoiding words: [String]) -> Day? {
        for row in rows {
            let lower = row.text.lowercased()
            guard !words.contains(where: { lower.contains($0) }) else { continue }
            if let day = DayParser.firstDay(in: row.text) { return day }
        }
        return nil
    }

    // MARK: Statements

    /// A statement's lines that start with a date and end with an amount.
    /// Years are often left off ("09/02"); they come from the statement's
    /// own closing date, stepping back a year for December lines on a
    /// January statement.
    static func statement(_ rows: [TextRow], recordId: UUID) -> ExtractedFacts {
        let rows = joiningAmountLines(rows)
        let closing = statementClosingDate(rows)
        var transactions: [Amount] = []

        for row in rows {
            guard let leading = DayParser.leadingDate(in: row.text),
                  let amount = MoneyParser.amounts(in: row.text).last else { continue }
            let ns = row.text as NSString
            let afterDate = leading.length
            guard amount.range.location > afterDate else { continue }

            var description = ns.substring(with: NSRange(location: afterDate, length: amount.range.location - afterDate))
            // A second (posting) date right after the first.
            if let second = DayParser.leadingDate(in: description) {
                description = (description as NSString).substring(from: second.length)
            }
            // Other amounts on the row (daily cash, running balance) and stray percentages.
            for other in MoneyParser.amounts(in: description).reversed() {
                description = (description as NSString).replacingCharacters(in: other.range, with: "")
            }
            description = description.replacingOccurrences(of: "\\s+\\d{1,2}%", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard description.count(where: \.isLetter) >= 2, !isSummaryLine(description) else { continue }

            let year: Int
            if let printed = leading.year {
                year = printed
            } else if let closing {
                year = leading.month > closing.month ? closing.year - 1 : closing.year
            } else {
                continue
            }
            guard let date = Day(year: year, month: leading.month, day: leading.day) else { continue }

            let kind = statementKind(description, amount: amount)
            transactions.append(Amount(
                recordId: recordId, pagePosition: row.pagePosition, linePosition: row.linePosition, date: date,
                merchant: merchantName(description), memo: description, amountCents: amount.cents,
                currency: amount.currency ?? "USD", kind: kind,
                // A payment isn't spending, so it has no spending category.
                category: kind == .payment ? .other : nil, source: .statement))
        }
        return ExtractedFacts(documentDate: closing, transactions: transactions)
    }

    /// A line that starts with a date but has no amount takes the lines
    /// after it that are only amounts or percentages, and, if the date was
    /// alone, the description line before them. The iPhone's PDF text for an
    /// Apple Card statement puts "06/29/2026 DD *DOORDASH … 2%" on one line
    /// and "$0.68" and "$34.18" on the next two; other readers put even the
    /// date on its own line.
    static func joiningAmountLines(_ rows: [TextRow]) -> [TextRow] {
        var joined: [TextRow] = []
        var index = 0
        while index < rows.count {
            var row = rows[index]
            index += 1
            guard DayParser.leadingDate(in: row.text) != nil, MoneyParser.amounts(in: row.text).isEmpty else {
                joined.append(row)
                continue
            }
            let dateLength = DayParser.leadingDate(in: row.text)?.length ?? 0
            let afterDate = (row.text as NSString).substring(from: min(dateLength, (row.text as NSString).length))
            if afterDate.count(where: \.isLetter) < 2, index < rows.count,
               DayParser.leadingDate(in: rows[index].text) == nil, !isOnlyAmounts(rows[index].text),
               MoneyParser.amounts(in: rows[index].text).isEmpty {
                row.text += " " + rows[index].text
                index += 1
            }
            while index < rows.count {
                let next = rows[index].text.trimmingCharacters(in: .whitespaces)
                // Amounts, and cash-back notes like "3% Daily Cash at Exxon Mobil".
                if isOnlyAmounts(next) || next.range(of: "^\\d{1,2}% ", options: .regularExpression) != nil {
                    row.text += " " + next
                    index += 1
                } else if columnHeaders.contains(next.lowercased()), MoneyParser.amounts(in: row.text).isEmpty {
                    // A column heading read in between: "Amount".
                    index += 1
                } else {
                    break
                }
            }
            joined.append(row)
        }
        return joined
    }

    static let columnHeaders: Set<String> = ["amount", "daily cash", "date", "description", "debit", "credit",
                                             "balance", "transaction date", "post date"]

    /// "$0.68", "-$2,316.54", "1%", "$0.09 $8.55": numbers and nothing else.
    static func isOnlyAmounts(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isLetter) || trimmed.hasSuffix("CR") else { return false }
        let leftover = trimmed.replacingOccurrences(of: "CR", with: "")
            .filter { !"0123456789$€£.,%-−() ".contains($0) }
        return leftover.isEmpty && (!MoneyParser.amounts(in: trimmed).isEmpty || trimmed.hasSuffix("%"))
    }

    /// The end of the statement period: the later date on a "period" or
    /// "closing" row, else the latest full date on the statement.
    static func statementClosingDate(_ rows: [TextRow]) -> Day? {
        for row in rows {
            let lower = row.text.lowercased()
            if ["closing date", "statement period", "billing period", "statement closing"].contains(where: { lower.contains($0) }),
               let latest = DayParser.days(in: row.text).map(\.day).max() {
                return latest
            }
        }
        // "Jun 1 — Jun 30, 2026", anywhere on a line: the year is printed once.
        let period = DayParser.regex("\\b([a-z]{3,9})\\.?\\s+\\d{1,2}\\s*[—–-]\\s*([a-z]{3,9})\\.?\\s+(\\d{1,2}),?\\s+(\\d{4})")
        for row in rows {
            let ns = row.text as NSString
            guard let m = period.firstMatch(in: row.text, range: NSRange(location: 0, length: ns.length)),
                  DayParser.month(named: ns.substring(with: m.range(at: 1))) != nil,
                  let month = DayParser.month(named: ns.substring(with: m.range(at: 2))),
                  let day = Int(ns.substring(with: m.range(at: 3))), let year = Int(ns.substring(with: m.range(at: 4))),
                  let end = Day(year: year, month: month, day: day) else { continue }
            return end
        }
        return rows.flatMap { DayParser.days(in: $0.text).map(\.day) }.max()
    }

    static func isSummaryLine(_ description: String) -> Bool {
        let lower = description.lowercased()
        return ["balance", "payment due", "minimum payment", "credit limit", "available credit",
                "total", "statement", "page "].contains { lower.hasPrefix($0) || lower == $0 }
    }

    static func statementKind(_ description: String, amount: ParsedAmount) -> AmountKind {
        let lower = description.lowercased()
        let paymentWords = ["payment", "ach deposit", "internet transfer", "transfer from", "autopay", "thank you"]
        if amount.isCredit, paymentWords.contains(where: { lower.contains($0) }) {
            return .payment
        }
        if lower.contains("payment"), ["thank", "autopay", "received", "ach"].contains(where: { lower.contains($0) }) {
            return .payment
        }
        if lower.contains("interest charge") || lower.contains(" fee") || lower.hasPrefix("fee") {
            return amount.isCredit ? .refund : .fee
        }
        return amount.isCredit ? .refund : .purchase
    }

    /// "SHELL OIL 57442" → "Shell"; "TRADER JOE'S #231" → "Trader Joe's";
    /// otherwise the description without store numbers, title-cased.
    static func merchantName(_ description: String) -> String {
        if let known = Suggester.knownName(inText: description) {
            return known
        }
        // Card-terminal prefixes ("TST*", "SQ *") aren't part of the name, and
        // anything after " - " is usually the location.
        var description = description.replacingOccurrences(
            of: "^(tst|sq|sp|py|pp|wl|in|ck|pos)\\s?\\*\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        if let dash = description.range(of: " - ") { description = String(description[..<dash.lowerBound]) }
        // The name, before the store number or street address starts.
        var words: [Substring] = []
        for word in description.split(separator: " ") {
            if word.hasPrefix("#") { continue }
            let mostlyDigits = word.count(where: \.isNumber) * 2 >= word.count
            if mostlyDigits {
                if words.isEmpty { continue } else { break }
            }
            words.append(word)
            if words.count == 4 { break }
        }
        let cleaned = words.joined(separator: " ")
        return cleaned.isEmpty ? description : Suggester.titleCased(cleaned)
    }
}

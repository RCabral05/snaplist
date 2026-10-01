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
}

/// Reads dates and amounts from receipts, bills and statements with plain
/// rules. It prefers missing a value to inventing one: a receipt with no
/// recognisable total gets no amount, and the person can type it in.
enum Extractor {
    static func extract(kind: RecordKind, pages: [RecognizedPage], recordId: UUID, merchant: String) -> ExtractedFacts {
        let rows = rows(of: pages)
        switch kind {
        case .receipt: return receipt(rows, recordId: recordId, merchant: merchant)
        case .bill: return bill(rows, recordId: recordId, merchant: merchant)
        case .statement: return statement(rows, recordId: recordId)
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
        return ExtractedFacts(documentDate: date, transactions: [transaction])
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

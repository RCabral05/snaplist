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
    var transactions: [Transaction] = []
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
    /// to right. Lines without boxes (a PDF's text layer) are rows already.
    static func rows(of page: RecognizedPage, pagePosition: Int) -> [TextRow] {
        var rows: [(text: String, line: Int, midY: Double, height: Double, minX: Double)] = []
        for (index, line) in page.lines.enumerated() {
            guard let box = line.box else {
                rows.append((line.text, index, Double(index), 0, 0))
                continue
            }
            let midY = box.y + box.height / 2
            if let last = rows.indices.last, rows[last].height > 0,
               abs(rows[last].midY - midY) < min(rows[last].height, box.height) * 0.6 {
                let joined = box.x >= rows[last].minX
                    ? "\(rows[last].text) \(line.text)" : "\(line.text) \(rows[last].text)"
                rows[last] = (joined, rows[last].line, rows[last].midY, max(rows[last].height, box.height),
                              min(rows[last].minX, box.x))
            } else {
                rows.append((line.text, index, midY, box.height, box.x))
            }
        }
        return rows.map { TextRow(text: $0.text, pagePosition: pagePosition, linePosition: $0.line) }
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
        let transaction = Transaction(
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
        let transaction = Transaction(
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
        var transactions: [Transaction] = []

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

            transactions.append(Transaction(
                recordId: recordId, pagePosition: row.pagePosition, linePosition: row.linePosition, date: date,
                merchant: merchantName(description), memo: description, amountCents: amount.cents,
                currency: amount.currency ?? "USD", kind: statementKind(description, amount: amount),
                source: .statement))
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
        // "Jul 1 — Jul 31, 2026": the year is only printed once.
        for row in rows {
            let text = row.text
            if let full = DayParser.days(in: text).first?.day,
               let range = text.range(of: "^\\s*([A-Za-z]{3,9})\\s+\\d{1,2}\\s*[—–-]", options: .regularExpression),
               DayParser.month(named: String(text[range]).trimmingCharacters(in: .letters.inverted)) != nil {
                return full
            }
        }
        return rows.flatMap { DayParser.days(in: $0.text).map(\.day) }.max()
    }

    static func isSummaryLine(_ description: String) -> Bool {
        let lower = description.lowercased()
        return ["balance", "payment due", "minimum payment", "credit limit", "available credit",
                "total", "statement", "page "].contains { lower.hasPrefix($0) || lower == $0 }
    }

    static func statementKind(_ description: String, amount: ParsedAmount) -> TransactionKind {
        let lower = description.lowercased()
        if lower.contains("payment") && (amount.isCredit || ["thank", "autopay", "received", "ach"].contains { lower.contains($0) }) {
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
        let page = RecognizedPage(lines: [RecognizedLine(text: description)], source: .pdfText)
        if let known = Suggester.knownName(in: page) {
            return known
        }
        let words = description.split(separator: " ").filter { word in
            !word.hasPrefix("#") && word.count(where: \.isNumber) * 2 < word.count
        }
        let cleaned = words.prefix(4).joined(separator: " ")
        return cleaned.isEmpty ? description : Suggester.titleCased(cleaned)
    }
}

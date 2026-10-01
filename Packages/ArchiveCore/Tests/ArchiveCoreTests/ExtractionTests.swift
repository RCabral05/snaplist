import Foundation
import Testing
@testable import ArchiveCore

private let id = UUID()

/// OCR-style lines: each `(text, x, y)` gets a box 0.02 high.
private func scan(_ lines: [(String, Double, Double)]) -> RecognizedPage {
    RecognizedPage(lines: lines.map { text, x, y in
        RecognizedLine(text: text, box: PageRect(x: x, y: y, width: 0.3, height: 0.02))
    }, source: .ocr)
}

private func pdf(_ lines: [String]) -> RecognizedPage {
    RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: .pdfText)
}

@Suite struct Days {
    @Test func parsesCommonFormats() {
        #expect(DayParser.firstDay(in: "09/28/2026 08:14") == Day(year: 2026, month: 9, day: 28))
        #expect(DayParser.firstDay(in: "9-5-26") == Day(year: 2026, month: 9, day: 5))
        #expect(DayParser.firstDay(in: "2026-04-14") == Day(year: 2026, month: 4, day: 14))
        #expect(DayParser.firstDay(in: "August 5, 2026") == Day(year: 2026, month: 8, day: 5))
        #expect(DayParser.firstDay(in: "Payment Due By Aug 31, 2026") == Day(year: 2026, month: 8, day: 31))
        #expect(DayParser.firstDay(in: "14 Sept 2026") == Day(year: 2026, month: 9, day: 14))
    }

    @Test func rejectsWhatIsNotADate() {
        #expect(DayParser.firstDay(in: "02/30/2026") == nil)
        #expect(DayParser.firstDay(in: "10.214 GAL") == nil)
        #expect(DayParser.firstDay(in: "REG#06 TRN#7478") == nil)
        #expect(DayParser.firstDay(in: "Card ending 4421") == nil)
    }

    @Test func statementRowsMayLeaveOutTheYear() {
        #expect(DayParser.leadingDate(in: "09/02  PG&E WEB ONLINE 160.43")?.month == 9)
        #expect(DayParser.leadingDate(in: "Jul 03 APPLE.COM/BILL 2.99")?.day == 3)
        #expect(DayParser.leadingDate(in: "07/02/2026 UBER 12.00")?.year == 2026)
        #expect(DayParser.leadingDate(in: "PG&E 09/02 160.43") == nil)
    }

    @Test func arithmeticAndRanges() {
        let day = Day(year: 2026, month: 12, day: 30)!
        #expect(day.adding(days: 3) == Day(year: 2027, month: 1, day: 2))
        #expect(day.days(to: Day(year: 2027, month: 1, day: 2)!) == 3)
        #expect(DayRange.month(2, of: 2028)?.end == Day(year: 2028, month: 2, day: 29))
        #expect(Day(iso: "2026-09-28")?.iso == "2026-09-28")
    }
}

@Suite struct Amounts {
    func cents(_ line: String) -> [Int64] { MoneyParser.amounts(in: line).map(\.cents) }

    @Test func findsMoneyNotQuantities() {
        #expect(cents("TOTAL               72.65") == [7265])
        #expect(cents("UNLEADED     10.214 GAL") == [])
        #expect(cents("$1,234.56 and €12,50") == [123456, 1250])
        #expect(cents("YOUR PANERA $25") == [2500])
        #expect(cents("QTY 2 @ 3.99") == [399])
        #expect(cents("09/28 08:14") == [])
        #expect(cents("Account ending 4421") == [])
    }

    @Test func credits() {
        let lines = ["Payments -$412.08", "RETURN (15.99)", "PAYMENT THANK YOU 160.43 CR"]
        #expect(lines.map { MoneyParser.amounts(in: $0).first?.isCredit } == [true, true, true])
        #expect(MoneyParser.amounts(in: "SHELL 39.82").first?.isCredit == false)
    }

    @Test func formatting() {
        #expect(MoneyParser.format(Money(cents: 123456)) == "$1,234.56")
        #expect(MoneyParser.format(Money(cents: 5)) == "$0.05")
    }
}

@Suite struct Receipts {
    @Test func totalSplitAcrossTwoObservationsOnOneRow() {
        // Vision often returns the label and the amount as separate lines.
        let page = scan([
            ("COSTCO WHOLESALE", 0.3, 0.05), ("09/25/2026 17:42", 0.2, 0.10),
            ("SUBTOTAL", 0.1, 0.60), ("69.25", 0.7, 0.601),
            ("TAX", 0.1, 0.63), ("3.40", 0.7, 0.631),
            ("TOTAL", 0.1, 0.66), ("72.65", 0.7, 0.661),
            ("VISA ****4421", 0.1, 0.70),
        ])
        let facts = Extractor.extract(kind: .receipt, pages: [page], recordId: id, merchant: "Costco")
        #expect(facts.documentDate == Day(year: 2026, month: 9, day: 25))
        #expect(facts.transactions.count == 1)
        let total = facts.transactions[0]
        #expect(total.amountCents == 7265)
        #expect(total.kind == .purchase)
        #expect(total.category == .groceries)
        #expect(total.linePosition == 6)
        #expect(total.date == Day(year: 2026, month: 9, day: 25))
    }

    @Test func fuelTotalAndPumpQuantities() {
        let page = pdf(["SHELL", "09/28/2026  08:14", "UNLEADED     10.214 GAL", "PRICE/GAL         3.899",
                        "FUEL TOTAL      $39.82", "VISA ************4421"])
        let facts = Extractor.extract(kind: .receipt, pages: [page], recordId: id, merchant: "Shell")
        #expect(facts.transactions.map(\.amountCents) == [3982])
        #expect(facts.transactions.first?.category == .fuel)
    }

    @Test func labelAndAmountOnConsecutiveRows() {
        let page = pdf(["BLUE BOTTLE", "Total", "$5.98", "Thank you"])
        let facts = Extractor.extract(kind: .receipt, pages: [page], recordId: id, merchant: "Blue Bottle")
        #expect(facts.transactions.map(\.amountCents) == [598])
    }

    @Test func noTotalMeansNoGuess() {
        let page = pdf(["CVS pharmacy", "August 5, 2026", "YOUR PANERA $25", "CARD/PRODUCT HAS A VALUE OF $25.00"])
        let facts = Extractor.extract(kind: .receipt, pages: [page], recordId: id, merchant: "CVS Pharmacy")
        #expect(facts.documentDate == Day(year: 2026, month: 8, day: 5))
        #expect(facts.transactions.isEmpty)
    }

    @Test func expiryDatesAreNotPurchaseDates() {
        let page = pdf(["STORE", "RETURN BY 10/30/2026", "09/30/2026", "TOTAL 4.00"])
        let facts = Extractor.extract(kind: .receipt, pages: [page], recordId: id, merchant: "Store")
        #expect(facts.documentDate == Day(year: 2026, month: 9, day: 30))
    }
}

@Suite struct Bills {
    @Test func amountDueAndStatementDate() {
        let page = pdf(["PG&E", "ENERGY STATEMENT", "ACCOUNT 0123456789-0", "STATEMENT DATE 08/29/2026",
                        "SERVICE 07/28/2026 - 08/26/2026", "ELECTRIC CHARGES     $142.37", "GAS CHARGES           $18.06",
                        "TOTAL AMOUNT DUE     $160.43", "DUE DATE 09/19/2026"])
        let facts = Extractor.extract(kind: .bill, pages: [page], recordId: id, merchant: "PG&E")
        #expect(facts.documentDate == Day(year: 2026, month: 8, day: 29))
        #expect(facts.transactions.map(\.amountCents) == [16043])
        #expect(facts.transactions.first?.kind == .bill)
        #expect(facts.transactions.first?.category == .utilities)
    }
}

@Suite struct Statements {
    @Test func chaseStyleRowsWithoutYears() {
        let pages = [
            pdf(["CHASE", "Freedom Visa Statement", "Statement period 08/29/2026 - 09/28/2026",
                 "Previous balance                $412.08", "Payments                       -$412.08"]),
            pdf(["Transactions", "09/02  PG&E WEB ONLINE              160.43", "09/05  SHELL OIL 57442               44.10",
                 "09/18  TRADER JOE'S #231             21.72", "09/20  PAYMENT THANK YOU            -412.08",
                 "09/25  COSTCO WHSE #423              72.65", "09/27  AMAZON MKTPL RETURN          -15.99"]),
        ]
        let facts = Extractor.extract(kind: .statement, pages: pages, recordId: id, merchant: "Chase")
        #expect(facts.documentDate == Day(year: 2026, month: 9, day: 28))

        let t = facts.transactions
        #expect(t.map(\.merchant) == ["PG&E", "Shell", "Trader Joe's", "Payment Thank You", "Costco", "Amazon"])
        #expect(t.map(\.amountCents) == [16043, 4410, 2172, 41208, 7265, 1599])
        #expect(t.map(\.kind) == [.purchase, .purchase, .purchase, .payment, .purchase, .refund])
        #expect(t.map(\.category) == [.utilities, .fuel, .groceries, .other, .groceries, .shopping])
        #expect(t.allSatisfy { $0.date?.month == 9 && $0.date?.year == 2026 })
        #expect(t.allSatisfy { $0.pagePosition == 1 })
    }

    @Test func appleCardStyleRowsWithFullDatesAndDailyCash() {
        let page = pdf(["Apple Card", "Statement", "Jul 1 — Jul 31, 2026",
                        "07/02/2026 APPLE.COM/BILL INFINITE LOOP CUPERTINO 1% $0.03 $2.99",
                        "07/14/2026 UBER *TRIP SAN FRANCISCO 2% $0.36 $18.20",
                        "07/20/2026 ACH DEPOSIT INTERNET TRANSFER FROM ACCOUNT ENDING IN 1234 -$500.00"])
        let facts = Extractor.extract(kind: .statement, pages: [page], recordId: id, merchant: "Apple Card")
        #expect(facts.documentDate == Day(year: 2026, month: 7, day: 31))
        #expect(facts.transactions.map(\.amountCents) == [299, 1820, 50000])
        #expect(facts.transactions.map(\.kind) == [.purchase, .purchase, .refund])
        #expect(facts.transactions[0].category == .subscriptions)
        #expect(facts.transactions[1].merchant == "Uber")
    }

    @Test func decemberLinesOnAJanuaryStatement() {
        let page = pdf(["Closing Date 01/05/2027", "12/28  NETFLIX.COM  15.49", "01/02  SHELL OIL  40.00"])
        let facts = Extractor.extract(kind: .statement, pages: [page], recordId: id, merchant: "Card")
        #expect(facts.transactions.map(\.date) == [Day(year: 2026, month: 12, day: 28), Day(year: 2027, month: 1, day: 2)])
    }
}

@Suite struct StoredTransactions {
    let shell = RecognizedPage(lines: [
        RecognizedLine(text: "SHELL", box: PageRect(x: 0.3, y: 0.05, width: 0.4, height: 0.05)),
        RecognizedLine(text: "09/28/2026 08:14", box: PageRect(x: 0.1, y: 0.15, width: 0.4, height: 0.02)),
        RecognizedLine(text: "FUEL TOTAL $39.82", box: PageRect(x: 0.1, y: 0.25, width: 0.6, height: 0.02)),
        RecognizedLine(text: "VISA 4421", box: PageRect(x: 0.1, y: 0.30, width: 0.4, height: 0.02)),
    ], source: .ocr)

    func ingest(_ tmp: TemporaryArchive, page: RecognizedPage, title: String = "Scan",
                at date: Date = Date(timeIntervalSince1970: 1_790_000_000)) throws -> UUID {
        let record = try tmp.archive.add(kind: .document, title: title, nameSource: .automatic,
                                         items: [ImportItem(type: .image, source: .data(Data([1])), fileExtension: "jpg")], at: date)
        let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
        try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: [page])], for: record.id)
        return record.id
    }

    @Test func readingTextStoresTheTotalAndDate() throws {
        let tmp = try TemporaryArchive()
        let recordId = try ingest(tmp, page: shell)
        let record = try #require(try tmp.archive.store.record(recordId))
        #expect(record.kind == .receipt)
        #expect(record.documentDate == Day(year: 2026, month: 9, day: 28))

        let transactions = try tmp.archive.store.transactions(of: recordId)
        #expect(transactions.map(\.amountCents) == [3982])
        #expect(transactions.first?.merchant == "Shell")
        #expect(transactions.first?.linePosition == 2)
    }

    @Test func correctionsSurviveReadingAgain() throws {
        let tmp = try TemporaryArchive()
        let recordId = try ingest(tmp, page: shell)
        var total = try #require(try tmp.archive.store.transactions(of: recordId).first)
        total.amountCents = 3999
        try tmp.archive.store.save(total)

        let asset = try #require(try tmp.archive.store.assets(of: recordId).first)
        try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: [shell])], for: recordId)
        #expect(try tmp.archive.store.transactions(of: recordId).map(\.amountCents) == [3999])
    }

    @Test func refilingReadsAmountsForTheNewKind() throws {
        let tmp = try TemporaryArchive()
        let page = pdf(["Blue Bottle", "Thanks", "Total", "$5.98"])
        let recordId = try ingest(tmp, page: page)
        var record = try #require(try tmp.archive.store.record(recordId))
        #expect(record.kind == .document)
        #expect(try tmp.archive.store.transactions(of: recordId).isEmpty)

        record.kind = .receipt
        try tmp.archive.store.update(record)
        #expect(try tmp.archive.store.transactions(of: recordId).map(\.amountCents) == [598])
    }

    @Test func recordsSortByTheirOwnDate() throws {
        let tmp = try TemporaryArchive()
        // Scanned first, but dated later.
        let shellId = try ingest(tmp, page: shell, at: Date(timeIntervalSince1970: 1_790_000_000))
        let august = pdf(["COSTCO", "08/05/2026", "TOTAL 10.00", "VISA"])
        let costcoId = try ingest(tmp, page: august, at: Date(timeIntervalSince1970: 1_790_100_000))
        #expect(try tmp.archive.store.records().map(\.id) == [shellId, costcoId])
    }

    @Test func handSetDatesStay() throws {
        let tmp = try TemporaryArchive()
        let recordId = try ingest(tmp, page: shell)
        try tmp.archive.store.setDocumentDate(Day(year: 2026, month: 1, day: 1), for: recordId)
        try tmp.archive.store.refreshSuggestions()
        #expect(try tmp.archive.store.record(recordId)?.documentDate == Day(year: 2026, month: 1, day: 1))
    }
}

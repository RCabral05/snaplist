import Foundation
import Testing
@testable import ArchiveCore

private let today = Day(year: 2026, month: 10, day: 1)!

@Suite struct Parsing {
    func spending(_ text: String) -> SpendingQuery? {
        if case .spending(let query) = QuestionParser.parse(text, today: today) { return query }
        return nil
    }

    @Test func gasInSeptember() throws {
        let query = try #require(spending("How much did I spend on gas in September?"))
        #expect(query.categories == [.fuel])
        #expect(query.range == DayRange.month(9, of: 2026))
        #expect(query.rangeLabel == "September 2026")
        #expect(query.merchantTerms.isEmpty)
        #expect(query.notes.count == 1)
    }

    @Test func electricBillInAugust() throws {
        let query = try #require(spending("What was my electric bill in August?"))
        #expect(query.categories == [.utilities])
        #expect(query.range == DayRange.month(8, of: 2026))
        #expect(query.merchantTerms.isEmpty)
    }

    @Test func merchantsAndRelativeDates() throws {
        let costco = try #require(spending("how much have I spent at Costco this year"))
        #expect(costco.merchantTerms == ["costco"])
        #expect(costco.range == DayRange.year(2026))

        let lastMonth = try #require(spending("total spending last month"))
        #expect(lastMonth.range == DayRange.month(9, of: 2026))

        // November hasn't happened yet this year, so it means last year's.
        let november = try #require(spending("what did I spend in November"))
        #expect(november.range == DayRange.month(11, of: 2025))

        let mayTheVerb = try #require(spending("how much may I have spent at Target"))
        #expect(mayTheVerb.range == nil)
        #expect(mayTheVerb.merchantTerms == ["target"])
    }

    @Test func whereAndWhen() {
        #expect(QuestionParser.parse("Where did I put the spare HDMI cable?", today: today)
                == .whereIs(terms: ["spare", "hdmi", "cable"]))
        #expect(QuestionParser.parse("When does the warranty on my TV expire?", today: today)
                == .expiry(terms: ["tv"]))
        #expect(QuestionParser.parse("Samsung model number", today: today) == .search("Samsung model number"))
    }
}

@Suite struct Answering {
    /// Records with stored text, read through the real pipeline.
    func archive(_ documents: [(String, RecordKind?, Date, [RecognizedPage])]) throws -> TemporaryArchive {
        let tmp = try TemporaryArchive()
        for (title, kind, date, pages) in documents {
            let record = try tmp.archive.add(kind: kind ?? .document, title: title, nameSource: kind == nil ? .automatic : .person,
                                             items: [ImportItem(type: .pdf, source: .data(Data([1])), fileExtension: "pdf")], at: date)
            let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
            try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: pages)], for: record.id)
        }
        return tmp
    }

    func pdf(_ lines: String...) -> RecognizedPage {
        RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: .pdfText)
    }

    let october1 = Date(timeIntervalSince1970: 1_790_812_800)

    var sample: [(String, RecordKind?, Date, [RecognizedPage])] {
        [
            ("Scan", nil, october1, [pdf("SHELL", "09/28/2026 08:14", "FUEL TOTAL $39.82", "VISA 4421")]),
            ("Scan", nil, october1, [pdf("SHELL", "08/20/2026", "FUEL TOTAL $51.00", "VISA 4421")]),
            ("Scan", nil, october1, [pdf("COSTCO WHOLESALE", "09/25/2026", "SUBTOTAL 69.25", "TAX 3.40", "TOTAL 72.65", "VISA")]),
            ("Scan", nil, october1, [pdf("PG&E", "ENERGY STATEMENT", "ACCOUNT NUMBER 0123", "STATEMENT DATE 08/29/2026",
                                         "TOTAL AMOUNT DUE $160.43", "DUE DATE 09/19/2026")]),
            ("Scan", nil, october1, [
                pdf("CHASE", "Freedom Visa Statement", "Statement period 08/29/2026 - 09/28/2026"),
                pdf("09/02  PG&E WEB ONLINE  160.43", "09/05  SHELL OIL 57442  44.10", "09/20  PAYMENT THANK YOU  -412.08",
                    "09/25  COSTCO WHSE #423  72.65", "09/27  SHELL OIL 57442  -5.00", "09/28  SHELL OIL 57442  39.82"),
            ]),
        ]
    }

    @Test func gasInSeptemberCountsEachPurchaseOnce() throws {
        let tmp = try archive(sample)
        guard case .spending(let query) = QuestionParser.parse("How much did I spend on gas in September?", today: today) else {
            Issue.record("not a spending question"); return
        }
        let answer = try tmp.archive.store.answer(query)

        // 44.10 (statement) + 39.82 (receipt, also on the statement) − 5.00 refund. August's 51.00 is out of range.
        #expect(answer.totals == [Money(cents: 4410 + 3982 - 500)])
        #expect(answer.counted.count == 3)
        #expect(answer.duplicates.count == 1)
        #expect(answer.duplicates.first?.kept.transaction.source == .receipt)
        #expect(answer.notes.contains { $0.contains("counted once") })
        #expect(answer.notes.contains { $0.contains("refund") })
        #expect(answer.counted.allSatisfy { $0.transaction.category == .fuel })
    }

    @Test func electricBillInAugustIsTheBill() throws {
        let tmp = try archive(sample)
        guard case .spending(let query) = QuestionParser.parse("What was my electric bill in August?", today: today) else {
            Issue.record("not a spending question"); return
        }
        let answer = try tmp.archive.store.answer(query)
        #expect(answer.totals == [Money(cents: 16043)])
        #expect(answer.counted.first?.record.title == "PG&E Bill")
        // The statement line for it posted in September, outside the range.
        #expect(answer.duplicates.isEmpty)
    }

    @Test func paymentsAreNeverSpending() throws {
        let tmp = try archive(sample)
        let answer = try tmp.archive.store.answer(SpendingQuery(range: DayRange.month(9, of: 2026), rangeLabel: "September 2026"))
        #expect(!answer.counted.contains { $0.transaction.kind == .payment })
        // Bill paid on the card counted once; Costco receipt and its line counted once.
        #expect(answer.duplicates.count == 2)
    }

    @Test func missingStatementsAreSaid() throws {
        let tmp = try archive(sample)
        let answer = try tmp.archive.store.answer(SpendingQuery(categories: [.fuel], range: DayRange.month(8, of: 2026),
                                                                rangeLabel: "August 2026"))
        #expect(answer.totals == [Money(cents: 5100)])
        #expect(answer.notes.contains { $0.contains("No card or bank statement") })
    }

    @Test func anEmptyMonthPointsToMonthsThatHaveSpending() throws {
        let tmp = try archive(sample)
        // October: nothing saved yet.
        let answer = try tmp.archive.store.answer(SpendingQuery(categories: [.fuel], range: DayRange.month(10, of: 2026),
                                                                rangeLabel: "October 2026"))
        #expect(answer.counted.isEmpty)
        #expect(answer.otherMonths.map(\.label) == ["September 2026", "August 2026"])
        // September counts the duplicated Shell purchase once: 44.10 + 39.82 − 5.00.
        #expect(answer.otherMonths.first?.totals == [Money(cents: 7892)])
        #expect(answer.otherMonths.last?.totals == [Money(cents: 5100)])
        #expect(answer.notes.contains { $0.contains("Your statements cover September 2026") })
    }

    @Test func statementsWithNothingReadAreMentioned() throws {
        let tmp = try archive([("Scan", nil, october1, [pdf("Card Statement", "Balance $10.00", "nothing on this page")])])
        let answer = try tmp.archive.store.answer(SpendingQuery(categories: [.fuel]))
        #expect(answer.counted.isEmpty)
        #expect(answer.notes.contains { $0.contains("no transactions read") })
    }

    @Test func nothingFoundIsEmptyNotZeroGuessing() throws {
        let tmp = try archive(sample)
        let answer = try tmp.archive.store.answer(SpendingQuery(merchantTerms: ["starbucks"]))
        #expect(answer.counted.isEmpty)
        #expect(answer.totals.isEmpty)
    }

    @Test func whereIsLooksAtItemsFirst() throws {
        let tmp = try archive([
            ("HDMI note", .item, october1, [pdf("Spare HDMI cable is in the hall closet, top shelf")]),
            ("TV manual", .manual, october1, [pdf("Connect an HDMI cable to port 2")]),
        ])
        let hits = try tmp.archive.store.whereIs(["spare", "hdmi", "cable"])
        #expect(hits.first?.record.title == "HDMI note")
    }

    @Test func expiryPrintedOrWorkedOut() throws {
        let tmp = try archive([
            ("Samsung TV warranty", .warranty, october1, [pdf("SAMSUNG", "LIMITED WARRANTY", "Smart TV QN65", "EXPIRES 04/14/2027")]),
            ("Blender warranty", .warranty, october1, [pdf("Vitamix", "Purchased 03/01/2026", "Coverage: 2 years")]),
        ])
        let tv = try tmp.archive.store.expiries(["tv"])
        #expect(tv.first?.day == Day(year: 2027, month: 4, day: 14))
        #expect(tv.first?.isCalculated == false)

        let blender = try tmp.archive.store.expiries(["blender"])
        #expect(blender.first?.day == Day(year: 2028, month: 3, day: 1))
        #expect(blender.first?.isCalculated == true)
    }
}

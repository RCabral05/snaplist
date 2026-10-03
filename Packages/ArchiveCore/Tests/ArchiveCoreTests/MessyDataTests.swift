import Foundation
import Testing
@testable import ArchiveCore

/// The awkward paperwork real life produces: OCR slips, tips written in,
/// "you saved" lines, returns, statements across New Year, other banks'
/// layouts, foreign currency, the same receipt photographed twice. All
/// made up.
@Suite struct MessyData {
    let tmp: TemporaryArchive
    var store: ArchiveStore { tmp.archive.store }

    init() throws { tmp = try TemporaryArchive() }

    @discardableResult
    func add(_ pages: [[String]], source: TextSource = .ocr) throws -> UUID {
        let record = try tmp.archive.add(kind: .document, title: "Scan", nameSource: .automatic,
                                         items: [ImportItem(type: .image, source: .data(Data([1])), fileExtension: "jpg")])
        let asset = try #require(try store.assets(of: record.id).first)
        try store.saveText([ExtractedAsset(assetId: asset.id, pages: pages.map { lines in
            RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: source)
        })], for: record.id)
        return record.id
    }

    func total(_ id: UUID) throws -> Int64? {
        let amounts = try store.transactions(of: id)
        return amounts.count == 1 ? amounts[0].amountCents : nil
    }

    func lines(_ id: UUID) -> [String] {
        ((try? store.transactions(of: id)) ?? []).map { "\($0.date?.iso ?? "-") \($0.memo) \($0.kind) \($0.amountCents)" }
    }

    // MARK: Receipts

    @Test func theTotalIsntTheSavingsOrTheItemCount() throws {
        let target = try add([["TARGET", "09/12/2026", "TIDE PODS  24.99", "BATH TOWEL  12.99", "SUBTOTAL  37.98",
                               "TOTAL SAVINGS  5.00", "TAX  3.56", "TOTAL  41.54", "TOTAL ITEMS 2", "VISA ****4421"]])
        #expect(try total(target) == 4154, "\(lines(target))")
        let cvs = try add([["CVS pharmacy", "09/14/2026", "ADVIL  12.99", "SUBTOTAL 12.99", "TOTAL TAX .81", "TOTAL 13.80",
                            "ExtraCare savings you saved $3.00", "MASTERCARD"]])
        #expect(try total(cvs) == 1380, "\(lines(cvs))")
    }

    @Test func ocrSlips() throws {
        // "T0TAL" with a zero, a space after the dollar sign, a comma in the thousands.
        let zero = try add([["HOME DEPOT", "08/02/2026", "LADDER 8FT  189.00", "SUBT0TAL 189.00", "TAX 11.81", "T0TAL $ 200.81", "VISA"]])
        #expect(try total(zero) == 20081, "\(lines(zero))")
        let big = try add([["BEST BUY", "08/03/2026", "LAPTOP  1,149.99", "SUBTOTAL 1,149.99", "TAX 107.81", "TOTAL 1,257.80", "VISA"]])
        #expect(try total(big) == 125_780, "\(lines(big))")
        let lower = try add([["trader joe's", "aug 4, 2026", "bananas 0.29", "total 0.29", "visa"]])
        #expect(try total(lower) == 29, "\(lines(lower))")
        #expect(try store.record(lower)?.title == "Trader Joe's")
    }

    @Test func aTipWrittenIn() throws {
        let dinner = try add([["MARIO'S PIZZERIA", "09/18/2026 19:42", "LARGE MARGHERITA  21.99", "SUBTOTAL  21.99", "TAX  2.06",
                               "AMOUNT  24.05", "TIP  5.00", "TOTAL  29.05", "VISA ****4421", "CUSTOMER COPY"]])
        #expect(try total(dinner) == 2905, "\(lines(dinner))")
        #expect(try store.transactions(of: dinner).first?.category == .dining)
        // The tip and the pre-tip amount aren't things ordered.
        #expect(try store.items(of: dinner).map(\.name) == ["Large Margherita"])
    }

    @Test func aReturnIsMoneyBack() throws {
        let back = try add([["TARGET", "09/20/2026", "RETURN", "BATH TOWEL  -12.99", "TAX  -1.22", "TOTAL  -14.21",
                             "REFUND TO VISA ****4421"]])
        let amount = try #require(try store.transactions(of: back).first, "\(lines(back))")
        #expect(amount.amountCents == 1421)
        #expect(amount.kind == .refund)
    }

    @Test func aReceiptInEuros() throws {
        let paris = try add([["CAFÉ DE FLORE", "172 BOULEVARD SAINT-GERMAIN", "14/07/2026", "2 CAFÉ CRÈME  11,00 €",
                              "CROISSANT  3,50 €", "TOTAL TTC  14,50 €", "CB VISA"]])
        let amount = try #require(try store.transactions(of: paris).first, "\(lines(paris))")
        #expect(amount.currency == "EUR")
        #expect(amount.amountCents == 1450)
        // 14/07: day first, since there's no 14th month.
        #expect(amount.date == Day(year: 2026, month: 7, day: 14))
    }

    @Test func theSameReceiptPhotographedTwice() throws {
        let receipt = ["COSTCO WHOLESALE", "09/25/2026 17:42", "ORGANIC EGGS 24  8.79", "SUBTOTAL 8.79", "TOTAL 8.79", "VISA"]
        try add([receipt])
        try add([receipt])
        let answer = try store.answer(SpendingQuery(merchantTerms: ["costco"]))
        #expect(answer.totals == [Money(cents: 879)], "counted \(answer.counted.count)")
    }

    @Test func aPlaceNamedOnTheReceiptButNotInTheStoreName() throws {
        // Made up: the shop's name is on top; "dispensary" only further down.
        let receipt = try add([["GREEN LEAF WELLNESS", "Licensed Cannabis Dispensary", "Lic# C10-0000000-LIC",
                                "09/26/2026 16:05", "Blue Dream 3.5g  35.00", "Pre-roll 1g  12.00", "SUBTOTAL  47.00",
                                "Excise tax  7.05", "Sales tax  4.41", "TOTAL  58.46", "DEBIT ****1234"]])
        #expect(try store.record(receipt)?.title == "Green Leaf Wellness")
        let today = Day(year: 2026, month: 10, day: 1)!

        // As the rules read it: a place.
        guard case .spending(let query) = QuestionParser.parse("How much have I spent at the dispensary", today: today) else {
            Issue.record("not a spending question"); return
        }
        #expect(try store.unknownMerchantTerms(query.merchantTerms).isEmpty)
        #expect(try store.answer(query).totals == [Money(cents: 5846)])

        // As Apple Intelligence read it on the phone: pharmacy at "dispensary".
        let read = try store.answer(SpendingQuery(categories: [.pharmacy], merchantTerms: ["dispensary"]))
        #expect(read.totals == [Money(cents: 5846)])
        #expect(read.query.categories.isEmpty)
        #expect(read.notes.contains { $0.contains("isn't filed") || $0.contains("is filed as") })

        // A word on no receipt at all is still an honest nothing.
        #expect(try store.answer(SpendingQuery(merchantTerms: ["casino"])).totals.isEmpty)
    }

    @Test func aDispensaryReceiptWithDiscountsAndAllotments() throws {
        // Made up, laid out like a real dispensary receipt: discounts under
        // each line, a discount total and grams above the total, the word
        // "dispensary" only in the fine print.
        let id = try add([["Bloom Example", "12 Sample St.", "Warwick, RI 02886", "10/2/2026 3:36:49 PM",
                           "Order: 00000000", "F(Popcorn)-Example Strain-7.0g (7.00g)", "Unit Price", "--Multiple Discounts",
                           "35.00", "-$10.15", "PR(Single)-Example Roll-1.0g-S (1.00g)", "Unit Price", "--Multiple Discounts",
                           "5.00", "-$0.26", "Subtotal: $40.00", "RI Sales Tax: $2.07", "Total Tax: $2.07",
                           "Total Discount: $10.41", "Rounding: $-0.01", "Total: $31.65", "Payment (Debit): $32.00",
                           "Due Customer: $0.35", "Total Items: 2", "Total Grams: 8.00", "Starting Allotment: 40.87g",
                           "Loyalty Points Earned: 32.00", "Thanks for shopping!", "All sales final unless defective.",
                           "Defective product returns accepted within 14 day", "s with proof of defect. Products can only be ret",
                           "urned at the dispensary where they were purchase", "d."]])
        #expect(try total(id) == 3165, "\(lines(id))")
        #expect(try store.record(id)?.documentDate == Day(year: 2026, month: 10, day: 2))
        // Named by the product line above "Unit Price", less its discount.
        let items = try store.items(of: id)
        #expect(items.map(\.name) == ["F(Popcorn)-Example Strain-7.0g (7.00g)", "PR(Single)-Example Roll-1.0g-S (1.00g)"],
                "\(items.map(\.name))")
        #expect(items.map(\.amountCents) == [2485, 474])
        // Only defective items go back: no return reminder.
        #expect(try store.upcomingDates(from: Day(year: 2026, month: 10, day: 2)!).isEmpty)
        guard case .spending(let query) = QuestionParser.parse("How much have I spent at the dispensary",
                                                               today: Day(year: 2026, month: 10, day: 3)!) else {
            Issue.record("not a spending question"); return
        }
        #expect(try store.answer(query).totals == [Money(cents: 3165)])

        // "What did I get there?": the things, not only the total.
        guard case .spending(let what) = QuestionParser.parse("What did I get at the dispensary",
                                                              today: Day(year: 2026, month: 10, day: 3)!) else {
            Issue.record("not a spending question"); return
        }
        #expect(what.listsItems)
        let got = try store.answer(what)
        #expect(got.itemsByRecord.first?.items.count == 2)
        #expect(got.totals == [Money(cents: 3165)])
    }

    @Test func pricesAndDiscountsOnTheSameRow() throws {
        let id = try add([["Example Shop", "10/2/2026", "F(Premium)-Example Sunset (3.50g)", "-3.5g-H", "1A42A0300000000000000000",
                           "Unit Price  25.00", "--Multiple Discounts  -$7.25", "Subtotal: $25.00", "Total: $17.75"]])
        #expect(try store.items(of: id).map(\.amountCents) == [1775])
        #expect(try store.items(of: id).first?.name == "F(Premium)-Example Sunset (3.50g)")
    }

    @Test func aSubtotalTheCameraMisread() throws {
        // A faint "b": the subtotal came out as something that isn't "subtotal".
        for subtotal in ["Su total: $239.00", "Su5total: $239.00", "Sutotal: $239.00", "Su btotal: $239.00", "Subtota1: $239.00"] {
            let id = try add([["Example Shop", "10/2/2026 3:36:49 PM", "Item  239.00", subtotal, "RI Sales Tax: $12.37",
                               "Tctal Tax: $12.37", "Total Discount: $62.30", "Rounding: $-0.02", "Total: $189.05",
                               "Payment (Debit): $190.00", "Due Customer: $0.95", "Total Items: 7", "Total Grams: 37.00",
                               "Loyalty Points Total: 244.00"]])
            #expect(try total(id) == 18905, "\(subtotal): \(lines(id))")
        }
    }

    @Test func aReturnThatNeverCameBack() throws {
        try add([["TARGET", "09/10/2026", "RETURN", "BATH TOWEL  -12.99", "TOTAL  -12.99", "REFUND TO VISA ****4421"]])
        try add([["TARGET", "09/12/2026", "RETURN", "LAMP  -30.00", "TOTAL  -30.00", "REFUND TO VISA ****4421"]])
        let statement = try add([["CHASE", "Freedom Visa Statement", "Statement period 09/01/2026 - 09/30/2026", "New balance $40.00"],
                                 ["09/05  NETFLIX.COM  15.49", "09/13  TARGET 00012345  -12.99", "09/20  SHELL OIL 57442  40.00"]],
                                source: .pdfText)
        let check = try #require(try store.statementCheck(statement))
        // The towel came back as a credit; the lamp didn't.
        #expect(check.missingRefunds.map(\.transaction.amountCents) == [3000])
        #expect(check.withoutReceipt.map(\.transaction.amountCents) == [4000, 1549])
    }

    // MARK: Statements

    @Test func aStatementAcrossNewYear() throws {
        let id = try add([["CHASE", "Freedom Visa Statement", "Statement period 12/05/2025 - 01/04/2026", "New balance $412.08"],
                          ["12/18  NETFLIX.COM  15.49", "12/28  SHELL OIL 57442  44.10", "01/02  STARBUCKS STORE 10442  5.45"]],
                         source: .pdfText)
        let days = try store.transactions(of: id).map(\.date)
        #expect(days == [Day(year: 2025, month: 12, day: 18), Day(year: 2025, month: 12, day: 28), Day(year: 2026, month: 1, day: 2)])
    }

    @Test func otherBanksLayouts() throws {
        let amex = try add([["AMERICAN EXPRESS", "Blue Cash Statement", "Closing Date 09/28/26", "New Balance $96.43"],
                            ["09/03/26 NETFLIX.COM LOS GATOS CA $15.49", "09/14/26 WHOLEFDS SJC 10231 $80.94"]], source: .pdfText)
        #expect(try store.transactions(of: amex).map(\.amountCents) == [1549, 8094], "\(lines(amex))")
        let citi = try add([["Citi", "Costco Anywhere Visa Statement", "Billing Period: 08/29/26-09/28/26", "Minimum Payment Due $25.00"],
                            ["Sep 03 NETFLIX.COM 15.49", "Sep 14 COSTCO WHSE #0423 72.65", "Sep 20 AUTOPAY THANK YOU -96.43"]],
                           source: .pdfText)
        let kinds = try store.transactions(of: citi).map { "\($0.amountCents) \($0.kind)" }
        #expect(kinds == ["1549 purchase", "7265 purchase", "9643 payment"], "\(lines(citi))")
    }

    @Test func aCheckingAccountStatement() throws {
        let bank = try add([["Bank of America", "Your Adv Plus Banking statement", "for September 1, 2026 to September 30, 2026",
                             "Beginning balance on September 1 $5,100.00", "Ending balance on September 30 $6,250.00"],
                            ["09/01/26 ZELLE PAYMENT TO OAK STREET PROPERTIES -2,400.00",
                             "09/15/26 ACME CORP DES:PAYROLL ID:000 3,150.00",
                             "09/16/26 Online Banking transfer to SAV 0000 -500.00",
                             "09/20/26 PG&E DES:WEB ONLINE -160.43"]], source: .pdfText)
        let found = try store.transactions(of: bank)
        #expect(found.count == 4, "\(lines(bank))")
        let spent = try store.answer(SpendingQuery(range: DayRange.month(9, of: 2026))).totals.first?.cents
        // Rent and the electric bill; not the paycheck, not the transfer.
        #expect(spent == Int64(240_000 + 16043), "\(lines(bank))")
    }

    // MARK: Filing

    @Test func whatEachThingIsFiledAs() throws {
        let cases: [([String], RecordKind?, String)] = [
            (["UNITED STATES OF AMERICA", "PASSPORT", "Date of expiration 13 Mar 2031"], .identity, "Passport"),
            (["NATIONAL GRID", "Account number 000-111", "Billing period Aug 1 - Aug 31, 2026", "Previous balance $88.12",
              "Payment received thank you", "Total amount due $91.40", "Due date 09/21/2026", "Therms used 22"], .bill, "National Grid Bill"),
            (["Xfinity", "Account Number 8000 0000 0000", "Statement date Sep 2, 2026", "Previous balance 80.00",
              "Payments -80.00", "New charges 80.00", "Amount due $80.00", "Please pay by Sep 22, 2026"], .bill, "Xfinity Bill"),
            (["DYSON", "2 YEAR LIMITED WARRANTY", "V15 Detect", "Registered 06/01/2026"], .warranty, "Dyson Warranty"),
            (["Instructions for use", "Troubleshooting", "Safety information", "Model KF-200"], .manual, "Instructions For Use"),
        ]
        var problems: [String] = []
        for (lines, kind, title) in cases {
            let id = try add([lines], source: .pdfText)
            let record = try #require(try store.record(id))
            if record.kind != kind ?? .document || record.title != title {
                problems.append("\(lines[0]): \(record.kind) \"\(record.title)\", expected \(kind.map { "\($0)" } ?? "document") \"\(title)\"")
            }
        }
        #expect(problems.isEmpty, Comment(rawValue: problems.joined(separator: "\n")))
    }
}

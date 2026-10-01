import Foundation
import Testing
@testable import ArchiveCore

private func pdf(_ lines: [String]) -> RecognizedPage {
    RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: .pdfText)
}

/// Statements and other records read through the real pipeline.
private func archive(_ documents: [[RecognizedPage]]) throws -> TemporaryArchive {
    let tmp = try TemporaryArchive()
    for pages in documents {
        let record = try tmp.archive.add(kind: .document, title: "Scan", nameSource: .automatic,
                                         items: [ImportItem(type: .pdf, source: .data(Data([1])), fileExtension: "pdf")])
        let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
        try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: pages)], for: record.id)
    }
    return tmp
}

private func statement(_ period: String, _ lines: [String]) -> [RecognizedPage] {
    [pdf(["CHASE", "Freedom Visa Statement", "Statement period \(period)"]), pdf(lines)]
}

private let threeMonths: [[RecognizedPage]] = [
    statement("06/01/2026 - 06/30/2026", [
        "06/03  NETFLIX.COM  15.49", "06/05  DOORDASH*DASHPASS  9.99", "06/08  DOORDASH*WENDYS  18.20",
        "06/14  SHELL OIL 57442  40.00", "06/20  DOORDASH*CHIPOTLE  22.10",
    ]),
    statement("07/01/2026 - 07/31/2026", [
        "07/03  NETFLIX.COM  15.49", "07/05  DOORDASH*DASHPASS  9.99", "07/09  DOORDASH*WENDYS  16.75",
        "07/22  SHELL OIL 57442  51.00", "07/25  AMAZON MKTPL  33.10", "07/26  AMAZON MKTPL  -33.10",
    ]),
    statement("08/01/2026 - 08/31/2026", [
        "08/03  NETFLIX.COM  17.99", "08/05  DOORDASH*DASHPASS  9.99", "08/30  PAYMENT THANK YOU  -300.00",
    ]),
]

@Suite struct Overview {
    @Test func monthsAddUpByCategory() throws {
        let tmp = try archive(threeMonths)
        let overview = try tmp.archive.store.spendingOverview()
        #expect(overview.currency == "USD")
        #expect(overview.months.map(\.label) == ["June 2026", "July 2026", "August 2026"])

        let june = overview.months[0]
        #expect(june.totalCents == 1549 + 999 + 1820 + 4000 + 2210)
        #expect(june.byCategory[.fuel] == 4000)
        #expect(june.byCategory[.dining] == Int64(999 + 1820 + 2210))

        // The refund cancels the purchase; the payment isn't spending.
        let july = overview.months[1]
        #expect(july.byCategory[.shopping] == 0)
        #expect(overview.months[2].totalCents == 1799 + 999)
    }

    @Test func emptyMonthsInBetweenAreKept() throws {
        let tmp = try archive([threeMonths[0], threeMonths[2]])
        #expect(try tmp.archive.store.spendingOverview().months.map(\.count) == [5, 0, 2])
        #expect(try tmp.archive.store.spendingOverview(months: 2).months.map(\.label) == ["July 2026", "August 2026"])
    }

    @Test func nothingSavedIsEmpty() throws {
        let tmp = try TemporaryArchive()
        #expect(try tmp.archive.store.spendingOverview().months.isEmpty)
        #expect(try tmp.archive.store.recurringCharges().isEmpty)
    }
}

@Suite struct Recurring {
    @Test func subscriptionsAreFoundAndOrdersAreNot() throws {
        let tmp = try archive(threeMonths)
        let charges = try tmp.archive.store.recurringCharges()
        let names = charges.map { "\($0.merchant) \($0.typicalCents)" }

        // Netflix went up but is still the same subscription; DashPass is
        // pulled out of the DoorDash orders by its fixed price.
        #expect(charges.count == 2, "\(names)")
        let netflix = try #require(charges.first { $0.merchant.lowercased().contains("netflix") })
        #expect(netflix.cadence == .monthly)
        #expect(netflix.typicalCents == 1799)
        #expect(netflix.yearlyCents == 1799 * 12)
        #expect(netflix.nextExpected == Day(year: 2026, month: 9, day: 3))
        let dashpass = try #require(charges.first { $0.typicalCents == 999 })
        #expect(dashpass.charges.count == 3)
        // Most expensive per year first.
        #expect(charges.first?.typicalCents == 1799)
    }

    @Test func irregularOrUnsteadyIsNotRecurring() {
        let record = Record(kind: .statement, title: "S", createdAt: Date(timeIntervalSince1970: 0), status: .ready)
        func charge(_ id: Int64, _ month: Int, _ day: Int, _ cents: Int64) -> Counted {
            Counted(transaction: Amount(id: id, recordId: record.id, date: Day(year: 2026, month: month, day: day),
                                        merchant: "Gym", amountCents: cents, kind: .purchase, source: .statement),
                    record: record)
        }
        #expect(ArchiveStore.recurring([charge(1, 6, 1, 3000), charge(2, 6, 15, 3000)]) == nil)
        #expect(ArchiveStore.recurring([charge(1, 6, 1, 3000), charge(2, 7, 1, 6000)]) == nil)
        #expect(ArchiveStore.recurring([charge(1, 6, 1, 3000)]) == nil)
        #expect(ArchiveStore.recurring([charge(1, 6, 30, 3000), charge(2, 7, 31, 3000)])?.cadence == .monthly)
    }

    @Test func monthsRollOver() {
        #expect(Day(year: 2026, month: 1, day: 31)!.addingMonths(1) == Day(year: 2026, month: 2, day: 28))
        #expect(Day(year: 2026, month: 12, day: 5)!.addingMonths(1) == Day(year: 2027, month: 1, day: 5))
        #expect(Day(year: 2026, month: 3, day: 5)!.addingMonths(-3) == Day(year: 2025, month: 12, day: 5))
    }
}

@Suite struct UpcomingDates {
    @Test func billsDueAndWarrantiesEnding() throws {
        let tmp = try archive([
            [pdf(["PG&E", "ENERGY STATEMENT", "ACCOUNT NUMBER 0123", "STATEMENT DATE 09/29/2026",
                  "TOTAL AMOUNT DUE $160.43", "DUE DATE 10/19/2026"])],
            [pdf(["PG&E", "ENERGY STATEMENT", "STATEMENT DATE 08/29/2026", "TOTAL AMOUNT DUE $151.00", "DUE DATE 09/19/2026"])],
            [pdf(["Apple Card Statement", "Jul 1 — Jul 31, 2026", "Minimum Payment Due $35.00", "Payment Due By Aug 31, 2026"])],
            [pdf(["SAMSUNG", "LIMITED WARRANTY", "Smart TV QN65", "EXPIRES 04/14/2027"])],
        ])
        let today = Day(year: 2026, month: 10, day: 1)!
        let dates = try tmp.archive.store.upcomingDates(from: today)
        #expect(dates.map(\.kind) == [.billDue, .warrantyEnds])
        #expect(dates[0].day == Day(year: 2026, month: 10, day: 19))
        #expect(dates[0].amount == Money(cents: 16043))
        #expect(dates[1].day == Day(year: 2027, month: 4, day: 14))

        // In August, the card's payment was still ahead.
        let august = try tmp.archive.store.upcomingDates(from: Day(year: 2026, month: 8, day: 1)!)
        #expect(august.contains { $0.record.kind == .statement && $0.day == Day(year: 2026, month: 8, day: 31) })
    }
}

import Foundation
import Testing
@testable import ArchiveCore

private func receipt(_ tmp: TemporaryArchive, _ lines: [String], title: String = "Scan") throws -> UUID {
    let record = try tmp.archive.add(kind: .document, title: title, nameSource: .automatic,
                                     items: [ImportItem(type: .pdf, source: .data(Data([1])), fileExtension: "pdf")])
    let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
    try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: [
        RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: .pdfText),
    ])], for: record.id)
    return record.id
}

private let october3 = Day(year: 2026, month: 10, day: 3)!

@Suite struct ReviewFixes {
    @Test func subscriptionsWithNoNextChargeSortLast() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        try store.addTrial(name: "Zeta Plus", priceCents: 999, cadence: .monthly, ends: october3)
        try store.addTrial(name: "Alpha Plus", priceCents: 499, cadence: .monthly, ends: october3)
        for var subscription in try store.subscriptions() {
            subscription.cancelledOn = october3
            try store.save(subscription)
        }
        // Two with no next charge used to crash the sort.
        #expect(try store.subscriptions().map(\.name) == ["Alpha Plus", "Zeta Plus"])
    }

    @Test func aDeletedAmountStaysDeleted() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        let id = try receipt(tmp, ["TARGET", "10/03/2026", "TOTAL $20.00", "VISA"])
        let amounts = try store.transactions(of: id)
        #expect(amounts.count == 1)
        try store.delete(transaction: try #require(amounts.first?.id), of: id)
        try store.refreshSuggestions()
        #expect(try store.transactions(of: id).isEmpty)
    }

    @Test func farFutureAndOversizedNumbersAreIgnored() {
        #expect(DayParser.days(in: "Valid thru 12/31/2199").isEmpty)
        #expect(DayParser.firstDay(in: "Date 10/03/2026") == october3)
        #expect(DayRange.month(12, of: 2200)?.end == Day(year: 2200, month: 12, day: 31))
        #expect(MoneyParser.amounts(in: "TOTAL $99999999999999999.99").isEmpty)
        #expect(MoneyParser.amounts(in: "Order 9999999999999999999").isEmpty)
        #expect(CSVStatement.cents("99999999999999999.00") == nil)
        #expect(CSVStatement.cents("-1,234.56") == -123_456)
    }

    @Test func differentStoresInOneCategoryAreNotDuplicates() {
        func amount(_ merchant: String, memo: String = "", source: AmountSource) -> Amount {
            Amount(recordId: UUID(), date: october3, merchant: merchant, memo: memo, amountCents: 2000, currency: "USD",
                   kind: .purchase, category: .dining, source: source)
        }
        #expect(!ArchiveStore.sameMerchant(amount("Chipotle", source: .receipt), amount("Panera Bread", source: .statement)))
        #expect(ArchiveStore.sameMerchant(amount("Whole Foods Market", source: .receipt), amount("Wholefds", source: .statement)))
        #expect(ArchiveStore.sameMerchant(amount("PG&E", source: .bill), amount("Pgande", memo: "PGANDE WEB ONLINE", source: .statement)))
        #expect(ArchiveStore.sameMerchant(amount("Mario's Pizzeria", source: .receipt), amount("Marios Pizzeria", source: .statement)))
        #expect(!ArchiveStore.sameMerchant(amount("Joe's Pizza", source: .receipt), amount("Domino's Pizza", source: .statement)))
    }

    @Test func liveChargesKeepTheirCurrency() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        try tmp.archive.addLive([LiveCharge(id: "E1", day: october3, description: "CAFE DE FLORE", merchant: "Cafe de Flore",
                                            amountCents: 1250, currency: "EUR")], feed: "Travel Card")
        try tmp.archive.addLive([LiveCharge(id: "U1", day: october3.adding(days: 1), description: "TARGET", merchant: "Target",
                                            amountCents: 2000)], feed: "Travel Card")
        let record = try #require(try store.records().first { $0.kind == .statement })
        let amounts = try store.transactions(of: record.id).sorted { $0.amountCents < $1.amountCents }
        #expect(amounts.map(\.currency) == ["EUR", "USD"])
    }

    @Test func taxReportCountsEachRecordOnceInOneCurrency() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        let laptop = try receipt(tmp, ["APPLE STORE", "03/02/2026", "TOTAL $1,000.00", "VISA"])
        let paris = try receipt(tmp, ["HOTEL LUTETIA", "04/02/2026", "TOTAL 200,00 €"])
        let desk = try receipt(tmp, ["IKEA", "05/02/2026", "TOTAL $100.00", "VISA"])
        try store.addTag("Business", kind: .tax, to: laptop)
        try store.addTag("Home Office", kind: .tax, to: laptop)
        try store.addTag("Business", kind: .tax, to: paris)
        try store.addTag("Home Office", kind: .tax, to: desk)
        let report = try store.taxReport(year: 2026)
        #expect(report.currency == "USD")
        #expect(report.groups.first { $0.purpose == "Business" }?.totalCents == 100_000)
        #expect(report.totalCents == 110_000)
    }

    @Test func deleteEverythingClearsSubscriptionsAndFeeds() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        try store.addTrial(name: "Example Plus", priceCents: 999, cadence: .monthly, ends: october3)
        try tmp.archive.addLive([LiveCharge(id: "A", day: october3, description: "TARGET", merchant: "Target", amountCents: 2000)],
                                feed: "Card")
        try store.deleteAll()
        #expect(try store.subscriptions().isEmpty)
        // The feed starts over instead of pointing at a deleted record.
        #expect(try tmp.archive.addLive([LiveCharge(id: "A", day: october3, description: "TARGET", merchant: "Target",
                                                    amountCents: 2000)], feed: "Card") == 1)
    }
}

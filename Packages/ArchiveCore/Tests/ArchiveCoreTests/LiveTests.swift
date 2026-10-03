import Foundation
import Testing
@testable import ArchiveCore

private let october3 = Day(year: 2026, month: 10, day: 3)!

@Suite struct ApplePayTaps {
    @Test func tapsGoOnTheCardsMonth() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        let coffee = try #require(LiveCharge.tap(merchant: "Starbucks", amount: "$5.45", on: october3))
        let gas = try #require(LiveCharge.tap(merchant: "Shell", amount: "40.00", on: october3))
        #expect(try tmp.archive.addLive([coffee, gas], feed: "Apple Card") == 2)

        let record = try #require(try store.records(kind: .statement).first)
        #expect(record.title == "Apple Card · October 2026")
        let lines = try store.transactions(of: record.id)
        #expect(lines.map(\.amountCents) == [545, 4000])
        #expect(lines.map(\.category) == [.dining, .fuel])
        #expect(lines.allSatisfy { $0.kind == .purchase && $0.source == .statement })

        // A correction sticks, and later taps still arrive.
        var fixed = lines[0]
        fixed.category = .groceries
        try store.save(fixed)
        let lunch = try #require(LiveCharge.tap(merchant: "Chipotle", amount: "$12.10", on: october3.adding(days: 1)))
        try tmp.archive.addLive([lunch], feed: "Apple Card")
        let after = try store.transactions(of: record.id)
        #expect(after.count == 3)
        #expect(after.first { $0.amountCents == 545 }?.category == .groceries)
        #expect(try store.records(kind: .statement).count == 1)

        // Another month, another statement; another card, another statement.
        try tmp.archive.addLive([try #require(LiveCharge.tap(merchant: "Target", amount: "$20", on: Day(year: 2026, month: 11, day: 1)!))],
                                feed: "Apple Card")
        try tmp.archive.addLive([coffee], feed: "Chase Freedom")
        #expect(Set(try store.records(kind: .statement).map(\.title))
                == ["Apple Card · October 2026", "Apple Card · November 2026", "Chase Freedom · October 2026"])
    }

    @Test func amountsAsWalletGivesThem() {
        #expect(LiveCharge.tap(merchant: "Café", amount: "4,50 €", on: october3)?.currency == "EUR")
        #expect(LiveCharge.tap(merchant: "Café", amount: "4,50 €", on: october3)?.amountCents == 450)
        #expect(LiveCharge.tap(merchant: "Target", amount: "-$3.00", on: october3)?.amountCents == -300)
        #expect(LiveCharge.tap(merchant: "Target", amount: "", on: october3) == nil)
    }

    @Test func aTapAndItsReceiptCountOnce() throws {
        let tmp = try TemporaryArchive()
        let record = try tmp.archive.add(kind: .document, title: "Scan", nameSource: .automatic,
                                         items: [ImportItem(type: .image, source: .data(Data([1])), fileExtension: "jpg")])
        let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
        try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: [RecognizedPage(lines: [
            "STARBUCKS", "10/03/2026", "GRANDE LATTE 5.45", "TOTAL 5.45", "VISA"].map { RecognizedLine(text: $0) }, source: .ocr)])],
            for: record.id)
        try tmp.archive.addLive([try #require(LiveCharge.tap(merchant: "Starbucks", amount: "$5.45", on: october3))], feed: "Apple Card")
        let answer = try tmp.archive.store.answer(SpendingQuery(range: DayRange.month(10, of: 2026)))
        #expect(answer.totals == [Money(cents: 545)])
        #expect(answer.duplicates.count == 1)
    }

    @Test func theStatementImportedLaterCountsOnce() throws {
        let tmp = try TemporaryArchive()
        try tmp.archive.addLive([try #require(LiveCharge.tap(merchant: "Shell", amount: "$40.00", on: october3))], feed: "Apple Card")
        let csv = try tmp.archive.add(kind: .statement, title: "Apple Card October", nameSource: .file,
                                      items: [ImportItem(type: .csv, source: .data(Data([1])), fileExtension: "csv")])
        let asset = try #require(try tmp.archive.store.assets(of: csv.id).first)
        try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: [RecognizedPage(lines: [
            "Transaction Date,Clearing Date,Description,Merchant,Category,Type,Amount (USD)",
            "10/03/2026,10/04/2026,SHELL OIL 57442,Shell,Gas,Purchase,40.00",
        ].map { RecognizedLine(text: $0) }, source: .file)])], for: csv.id)
        #expect(try tmp.archive.store.answer(SpendingQuery(categories: [.fuel])).totals == [Money(cents: 4000)])
    }
}

@Suite struct SimpleFIN {
    /// Made up, in SimpleFIN's shape.
    let json = """
    {"errors": [], "accounts": [
      {"org": {"name": "Example Bank", "domain": "example.com"}, "id": "ACT-1", "name": "Rewards Visa", "currency": "USD",
       "balance": "-512.20", "balance-date": 1791100000, "transactions": [
         {"id": "T1", "posted": 1791000000, "amount": "-12.34", "description": "STARBUCKS STORE 10442", "payee": "Starbucks"},
         {"id": "T2", "posted": 1791010000, "amount": "500.00", "description": "PAYMENT THANK YOU"},
         {"id": "T3", "posted": 1791020000, "amount": "10.00", "description": "TARGET RETURN"},
         {"id": "T4", "posted": 1791030000, "amount": "-30.00", "description": "SHELL OIL", "pending": true}]},
      {"org": {"name": "Example Bank"}, "id": "ACT-2", "name": "Example Bank Checking", "currency": "USD",
       "transactions": [
         {"id": "C1", "posted": 1791000000, "amount": "3150.00", "description": "ACME CORP DIRECT DEP"},
         {"id": "C2", "posted": 1791000000, "amount": "-2400.00", "description": "ZELLE TO OAK STREET PROPERTIES"},
         {"id": "C3", "posted": 1791000000, "amount": "25.00", "description": "VENMO FROM ALEX"}]}
    ]}
    """

    @Test func accountsBecomeStatements() throws {
        let response = try JSONDecoder().decode(SimpleFINResponse.self, from: Data(json.utf8))
        let feeds = response.charges()
        #expect(feeds.map(\.feed) == ["Example Bank Rewards Visa", "Example Bank Checking"])
        let card = feeds[0].charges
        #expect(card.map(\.amountCents) == [1234, -50000, -1000])
        #expect(card.map(\.isPayment) == [false, true, false])
        // On a checking account, money in is income, not a refund.
        #expect(feeds[1].charges.map(\.isPayment) == [true, false, true])

        let tmp = try TemporaryArchive()
        for (feed, charges) in feeds { try tmp.archive.addLive(charges, feed: feed) }
        // Syncing again adds nothing.
        var again = 0
        for (feed, charges) in feeds { again += try tmp.archive.addLive(charges, feed: feed) }
        #expect(again == 0)

        let spent = try tmp.archive.store.answer(SpendingQuery()).totals
        // Starbucks less the Target return, plus rent; not the payment, the paycheck or Venmo.
        #expect(spent == [Money(cents: 1234 - 1000 + 240_000)])
    }

    @Test func setupTokens() {
        let token = Data("https://bridge.example.com/simplefin/claim/ABC".utf8).base64EncodedString()
        #expect(SimpleFINResponse.claimURL(fromSetupToken: " \(token)\n")?.host == "bridge.example.com")
        #expect(SimpleFINResponse.claimURL(fromSetupToken: "not a token") == nil)
    }
}

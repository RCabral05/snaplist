import Foundation
import GRDB
import Testing
@testable import ArchiveCore

private func add(_ tmp: TemporaryArchive, kind: RecordKind = .document, title: String = "Scan", _ lines: [String],
                 source: TextSource = .pdfText, type: AssetType = .pdf) throws -> UUID {
    let record = try tmp.archive.add(kind: kind, title: title, nameSource: kind == .document ? .automatic : .person,
                                     items: [ImportItem(type: type, source: .data(Data([1])), fileExtension: type == .csv ? "csv" : "pdf")])
    let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
    try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: [
        RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: source),
    ])], for: record.id)
    return record.id
}

private let today = Day(year: 2026, month: 10, day: 1)!

@Suite struct ThingProfiles {
    @Test func aTVWithItsPaperwork() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        let receipt = try add(tmp, kind: .receipt, title: "Best Buy", ["BEST BUY", "03/10/2026", "LG OLED65C4 TV  1,299.99",
                                                                        "SUBTOTAL 1,299.99", "TOTAL $1,299.99", "VISA 4421"])
        let warranty = try add(tmp, kind: .warranty, title: "LG warranty", ["LG ELECTRONICS", "LIMITED WARRANTY",
                                                                            "Model OLED65C4", "Coverage ends 03/10/2028"])
        let manual = try add(tmp, kind: .manual, title: "Owner's manual", ["OLED65C4 OWNER'S MANUAL", "Safety instructions"])
        let unrelated = try add(tmp, kind: .receipt, title: "Costco", ["COSTCO", "TOTAL 72.65", "VISA"])

        let item = try #require(try store.items(of: receipt).first)
        var tv = try #require(try store.draftThing(from: receipt, item: item))
        #expect(tv.name == "LG OLED65C4 TV")
        #expect(tv.valueCents == 129999)
        #expect(tv.store == "Best Buy")
        #expect(tv.purchased == Day(year: 2026, month: 3, day: 10))
        tv.room = "Living room"
        try store.createThing(tv, from: receipt)

        // The model number finds the warranty and the manual, not Costco.
        let suggested = try store.suggestedLinks(for: tv.id).map(\.id)
        #expect(Set(suggested) == [warranty, manual])
        #expect(!suggested.contains(unrelated))
        try store.link(warranty, to: tv.id)
        try store.link(manual, to: tv.id)

        let profile = try #require(try store.thingProfile(tv.id))
        #expect(profile.links.map(\.role) == [.receipt, .warranty, .manual])
        #expect(profile.warrantyEnds == Day(year: 2028, month: 3, day: 10))
        #expect(profile.warranty(on: today) == .covered(until: Day(year: 2028, month: 3, day: 10)!))
        #expect(try store.things(linkedTo: warranty).map(\.id) == [tv.id])
    }

    @Test func questionsAboutAThing() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        let receipt = try add(tmp, kind: .receipt, title: "Best Buy", ["BEST BUY", "03/10/2024", "TOTAL $1,299.99", "VISA"])
        try store.createThing(Thing(name: "LG TV", valueCents: 129999, purchased: Day(year: 2024, month: 3, day: 10),
                                    warrantyEnds: Day(year: 2025, month: 3, day: 10)), from: receipt)
        let blender = try add(tmp, kind: .receipt, title: "Target", ["TARGET", "08/01/2026", "TOTAL $99.00", "VISA"])
        try store.createThing(Thing(name: "Vitamix blender", warrantyEnds: Day(year: 2033, month: 8, day: 1)), from: blender)

        #expect(try store.thingQuestion("When did I buy my TV?", today: today)?.topic == .bought)
        #expect(try store.thingQuestion("Is my TV still under warranty?", today: today)?.topic == .warranty)
        #expect(try store.thingQuestion("Show me the receipt for my TV", today: today)?.topic == .documents)
        #expect(try store.thingQuestion("When did I buy my TV?", today: today)?.profiles.first?.thing.name == "LG TV")
        #expect(try store.thingQuestion("How much did I spend on gas", today: today) == nil)

        let ended = try #require(try store.thingQuestion("What things are no longer under warranty?", today: today))
        #expect(ended.isOutOfWarrantyList)
        #expect(ended.profiles.map(\.thing.name) == ["LG TV"])
    }

    @Test func inventoryItemsBecomeThings() throws {
        // A database from 2.3, with a home inventory item.
        let queue = try DatabaseQueue()
        try ArchiveStore.migrator.migrate(queue, upTo: "v8-line-items")
        let record = UUID()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO record (id, kind, title, createdAt, status, nameSource) VALUES (?, 'receipt', 'Best Buy', '2026-03-01', 'ready', 'person')",
                           arguments: [record])
            try db.execute(sql: "INSERT INTO belonging (recordId, name, valueCents, currency, serialNumber, room, purchased) VALUES (?, 'Samsung TV', 129999, 'USD', 'ABC123', 'Den', '2026-03-01')",
                           arguments: [record])
        }
        let store = try ArchiveStore(db: queue)
        let profile = try #require(try store.thingProfiles().first)
        #expect(profile.thing.name == "Samsung TV")
        #expect(profile.thing.room == "Den")
        #expect(profile.links.map(\.role) == [.receipt])
    }
}

@Suite struct PriceChanges {
    @Test func aBillThatWentUp() throws {
        let tmp = try TemporaryArchive()
        _ = try add(tmp, kind: .bill, title: "Verizon", ["VERIZON", "STATEMENT DATE 08/05/2026", "Unlimited Plus  80.00",
                                                         "Device payment  41.67", "Taxes and fees  20.33", "TOTAL AMOUNT DUE $142.00"])
        _ = try add(tmp, kind: .bill, title: "Verizon", ["VERIZON", "STATEMENT DATE 09/05/2026", "Unlimited Plus  90.00",
                                                         "Device payment  41.67", "Disney Bundle  10.00", "Taxes and fees  24.33",
                                                         "TOTAL AMOUNT DUE $166.00"])
        let change = try #require(try tmp.archive.store.priceChanges().first)
        #expect(change.kind == .bill)
        #expect(change.deltaCents == 2400)
        #expect(change.percent == 17)
        #expect(change.lines.map(\.name) == ["Unlimited Plus", "Disney Bundle", "Taxes and fees"])
        #expect(change.lines.first?.before == 8000)
        #expect(change.lines[1].before == nil)
    }

    @Test func aSubscriptionThatWentUp() throws {
        let tmp = try TemporaryArchive()
        for (month, amount) in [(6, "15.49"), (7, "15.49"), (8, "17.99")] {
            _ = try add(tmp, ["CHASE", "Freedom Visa Statement", String(format: "Statement period %02d/01/2026 - %02d/28/2026", month, month),
                              String(format: "%02d/03  NETFLIX.COM  ", month) + amount])
        }
        let change = try #require(try tmp.archive.store.priceChanges().first)
        #expect(change.kind == .subscription)
        #expect(change.previous.transaction.amountCents == 1549)
        #expect(change.latest.transaction.amountCents == 1799)
    }

    @Test func smallChangesArentNews() {
        #expect(!ArchiveStore.isMeaningful(14200, 14250))
        #expect(ArchiveStore.isMeaningful(14200, 16600))
    }
}

@Suite struct PriceMemory {
    @Test func whatEggsCostOverTime() throws {
        let tmp = try TemporaryArchive()
        _ = try add(tmp, ["COSTCO WHOLESALE", "06/10/2026", "ORGANIC EGGS 24  7.49", "TOTAL 7.49", "VISA 4421"])
        _ = try add(tmp, ["TRADER JOE'S", "07/10/2026", "EGGS DOZEN  3.99", "TOTAL 3.99", "VISA 4421"])
        _ = try add(tmp, ["COSTCO WHOLESALE", "09/10/2026", "ORGANIC EGGS 24  8.79", "TOTAL 8.79", "VISA 4421"])

        let question = QuestionParser.parse("What did I pay for eggs last time?", today: today)
        #expect(question == .priceHistory(terms: ["eggs"], categories: []))
        let history = try #require(try tmp.archive.store.priceHistory(["eggs"]))
        #expect(history.points.count == 3)
        #expect(history.latest?.transaction.amountCents == 879)
        #expect(history.lowest?.transaction.merchant == "Trader Joe's")
        #expect(history.changeCents == 130)

        #expect(QuestionParser.parse("Cheapest place I've bought Tide?", today: today) == .priceHistory(terms: ["tide"], categories: []))
    }

    @Test func gasAsWholePurchases() throws {
        let tmp = try TemporaryArchive()
        _ = try add(tmp, ["SHELL", "09/20/2026", "UNLEADED 10.214 GAL", "FUEL TOTAL $39.82", "VISA 4421"])
        _ = try add(tmp, ["SHELL", "09/28/2026", "UNLEADED 12.0 GAL", "FUEL TOTAL $46.80", "VISA 4421"])
        guard case .priceHistory(let terms, let categories) = QuestionParser.parse("What do I normally pay for gas?", today: today)
        else { Issue.record("not a price question"); return }
        #expect(categories == [.fuel])
        let history = try #require(try tmp.archive.store.priceHistory(terms, categories: categories))
        #expect(history.isPurchases)
        #expect(history.averageCents == (3982 + 4680) / 2)
    }
}

@Suite struct Collections {
    @Test func carCollectionGathersAndCounts() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        let oil = try add(tmp, kind: .receipt, title: "Jiffy Lube", ["JIFFY LUBE", "08/12/2026", "Oil change synthetic  79.99",
                                                                      "TOTAL $79.99", "VISA"])
        let registration = try add(tmp, kind: .identity, title: "Registration", ["VEHICLE REGISTRATION", "Expires 05/31/2027"])
        let card = try add(tmp, kind: .receipt, title: "Apple Store", ["APPLE STORE", "Apple Card payment", "TOTAL $20.00", "VISA"])
        _ = try add(tmp, ["CHASE", "Freedom Visa Statement", "Statement period 09/01/2026 - 09/30/2026",
                          "09/14  CITY CAR WASH  15.00", "09/20  NETFLIX.COM  15.49"])

        var car = try #require(Collection.presets.first { $0.name == "Car" })
        try store.save(car)
        let records = try store.records(in: car).map(\.id)
        #expect(Set(records) == [oil, registration])
        #expect(!records.contains(card))

        // By hand: left out and put in.
        try store.setRecord(registration, in: car.id, included: false)
        try store.setRecord(card, in: car.id, included: true)
        #expect(Set(try store.records(in: car).map(\.id)) == [oil, card])
        try store.setRecord(registration, in: car.id, included: nil)
        try store.setRecord(card, in: car.id, included: nil)

        // Spending: the oil change, and the car wash line on the statement.
        let answer = try store.answer(SpendingQuery().within(car, records: try store.records(in: car)))
        #expect(answer.totals == [Money(cents: 7999 + 1500)])
        #expect(try store.statementLines(in: car).map(\.transaction.amountCents) == [1500])

        #expect(try store.collection(namedIn: "How much have I spent on my car?")?.name == "Car")
        #expect(try store.collection(namedIn: "how much on groceries") == nil)
        car.keywords = "car, detailing"
        try store.save(car)
        #expect(try store.collections().first?.keywordList == ["car", "detailing"])
    }
}

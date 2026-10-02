import Foundation
import Testing
@testable import ArchiveCore

private func add(_ tmp: TemporaryArchive, kind: RecordKind = .document, title: String = "Scan", _ lines: [String]) throws -> UUID {
    let record = try tmp.archive.add(kind: kind, title: title, nameSource: kind == .document ? .automatic : .person,
                                     items: [ImportItem(type: .pdf, source: .data(Data([1])), fileExtension: "pdf")])
    let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
    try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: [
        RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: .pdfText),
    ])], for: record.id)
    return record.id
}

private let costco = ["COSTCO WHOLESALE", "SAN JOSE #423", "09/25/2026 17:42", "KS PAPER TOWEL      21.99",
                      "AA BATTERIES 48     17.49 E", "ROTISSERIE CHKN      4.99", "ORGANIC EGGS 24      8.79",
                      "OLIVE OIL 2L        15.99", "SUBTOTAL            69.25", "TAX                  3.40",
                      "TOTAL               72.65", "VISA ************4421", "CHANGE DUE 0.00"]

@Suite struct ReceiptItems {
    @Test func linesAboveTheTotal() throws {
        let tmp = try TemporaryArchive()
        let id = try add(tmp, costco)
        let items = try tmp.archive.store.items(of: id)
        #expect(items.map(\.name) == ["KS Paper Towel", "AA Batteries 48", "Rotisserie Chkn", "Organic Eggs 24", "Olive Oil 2L"])
        #expect(items.map(\.amountCents) == [2199, 1749, 499, 879, 1599])
        // Fuel receipts have no items, only gallons and a price per gallon.
        let shell = try add(tmp, ["SHELL", "09/28/2026 08:14", "UNLEADED 10.214 GAL", "PRICE/GAL 3.899", "FUEL TOTAL $39.82"])
        #expect(try tmp.archive.store.items(of: shell).isEmpty)
    }

    @Test func spendingOnAnItem() throws {
        let tmp = try TemporaryArchive()
        _ = try add(tmp, costco)
        guard case .spending(let query) = QuestionParser.parse("How much did I spend on eggs?", today: Day(year: 2026, month: 10, day: 1)!)
        else { Issue.record("not spending"); return }
        let answer = try tmp.archive.store.answer(query)
        #expect(answer.totals == [Money(cents: 879)])
        #expect(answer.counted.first?.transaction.memo == "Organic Eggs 24")
        #expect(answer.notes.contains { $0.contains("1 item") })

        // Asking about the store counts the receipt once, not its items too.
        let store = try tmp.archive.store.answer(SpendingQuery(merchantTerms: ["costco"]))
        #expect(store.totals == [Money(cents: 7265)])
    }

    @Test func whenDidILastBuy() throws {
        let tmp = try TemporaryArchive()
        _ = try add(tmp, costco)
        _ = try add(tmp, ["COSTCO WHOLESALE", "08/10/2026", "ORGANIC EGGS 24      7.99", "TOTAL 7.99", "VISA 4421"])
        let question = QuestionParser.parse("When did I last buy eggs?", today: Day(year: 2026, month: 10, day: 1)!)
        #expect(question == .lastBought(terms: ["eggs"]))
        let found = try tmp.archive.store.lastBought(["eggs"])
        #expect(found.map(\.transaction.amountCents) == [879, 799])
        #expect(found.first?.day == Day(year: 2026, month: 9, day: 25))
    }

    @Test func oldReceiptsGetTheirItems() throws {
        let tmp = try TemporaryArchive()
        let id = try add(tmp, costco)
        try tmp.archive.store.db.write { try $0.execute(sql: "DELETE FROM lineItem") }
        #expect(try tmp.archive.store.refreshItems() == 1)
        #expect(try tmp.archive.store.items(of: id).count == 5)
    }
}

@Suite struct ImportantDocuments {
    @Test func idsAndPoliciesWithExpiry() throws {
        let tmp = try TemporaryArchive()
        let license = try add(tmp, ["STATE OF RHODE ISLAND", "DRIVER LICENSE", "DOB 03/14/1995",
                                    "4a ISS 06/14/2022 4b EXP 06/14/2030"])
        let policy = try add(tmp, ["ACME AUTO INSURANCE", "Declarations Page", "Policy number 123-456",
                                   "Policy period 10/15/2026 to 04/15/2027"])
        let store = tmp.archive.store
        #expect(try store.record(license)?.kind == .identity)
        #expect(try store.record(license)?.documentDate == Day(year: 2022, month: 6, day: 14))
        #expect(try store.record(policy)?.kind == .identity)

        let documents = try store.importantDocuments()
        #expect(documents.map(\.record.id) == [policy, license])
        #expect(documents.first?.expires == Day(year: 2027, month: 4, day: 15))
        #expect(documents.last?.expires == Day(year: 2030, month: 6, day: 14))

        let upcoming = try store.upcomingDates(from: Day(year: 2026, month: 10, day: 1)!)
        #expect(upcoming.filter { $0.kind == .renewal }.map(\.record.id) == [policy, license])
    }

    @Test func expiryLabelsDontMatchOtherWords() {
        let rows = ["Business expenses 01/02/2026", "Valid through 12/31/2028"].enumerated()
            .map { TextRow(text: $1, pagePosition: 0, linePosition: $0) }
        #expect(ArchiveStore.printedExpiry(in: rows)?.day == Day(year: 2028, month: 12, day: 31))
    }
}

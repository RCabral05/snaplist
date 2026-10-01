import Foundation
import GRDB
import Testing
@testable import ArchiveCore

private let today = Day(year: 2026, month: 10, day: 1)!
private let october1 = Date(timeIntervalSince1970: 1_790_812_800)

private func pdf(_ lines: String...) -> RecognizedPage {
    RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: .pdfText)
}

/// A Shell receipt, a statement with the same purchase on it, and a
/// DoorDash line.
private func sampleArchive() throws -> (TemporaryArchive, receipt: UUID, statement: UUID) {
    let tmp = try TemporaryArchive()
    var ids: [UUID] = []
    for pages in [
        [pdf("SHELL", "09/28/2026 08:14", "FUEL TOTAL $39.82", "VISA 4421")],
        [pdf("CHASE", "Freedom Visa Statement", "Statement period 08/29/2026 - 09/28/2026"),
         pdf("09/05  SHELL OIL 57442  44.10", "09/12  DOORDASH*CVS  23.10", "09/20  DOORDASH*WENDYS  18.00",
             "09/28  SHELL OIL 57442  39.82")],
    ] {
        let record = try tmp.archive.add(kind: .document, title: "Scan", nameSource: .automatic,
                                         items: [ImportItem(type: .pdf, source: .data(Data([1])), fileExtension: "pdf")], at: october1)
        let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
        try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: pages)], for: record.id)
        ids.append(record.id)
    }
    return (tmp, ids[0], ids[1])
}

private func gasInSeptember(_ store: ArchiveStore) throws -> SpendingAnswer {
    try store.answer(SpendingQuery(categories: [.fuel], range: DayRange.month(9, of: 2026), rangeLabel: "September 2026"))
}

@Suite struct DuplicateDecisionsTests {
    @Test func aGuessIsShownOnBothRecords() throws {
        let (tmp, receipt, statement) = try sampleArchive()
        let onReceipt = try tmp.archive.store.possibleDuplicates(involving: receipt)
        #expect(onReceipt.count == 1)
        #expect(onReceipt.first?.decision == nil)
        #expect(try tmp.archive.store.possibleDuplicates(involving: statement).map(\.id) == onReceipt.map(\.id))
    }

    @Test func differentPurchasesBothCount() throws {
        let (tmp, receipt, _) = try sampleArchive()
        let store = tmp.archive.store
        #expect(try gasInSeptember(store).totals == [Money(cents: 4410 + 3982)])

        let pair = try #require(try store.possibleDuplicates(involving: receipt).first)
        try store.decide(pair, isSame: false)

        let answer = try gasInSeptember(store)
        #expect(answer.totals == [Money(cents: 4410 + 3982 + 3982)])
        #expect(answer.duplicates.isEmpty)
        #expect(answer.notes.contains { $0.contains("you said they're different") })
        // Still listed, so it can be changed back.
        #expect(try store.possibleDuplicates(involving: receipt).first?.decision == false)

        try store.decide(pair, isSame: nil)
        #expect(try gasInSeptember(store).totals == [Money(cents: 4410 + 3982)])
    }

    @Test func decisionsSurviveReadingTheStatementAgain() throws {
        let (tmp, receipt, statement) = try sampleArchive()
        let store = tmp.archive.store
        try store.decide(try #require(try store.possibleDuplicates(involving: receipt).first), isSame: false)

        // Reading again replaces every amount row with new ids.
        let pages = try store.db.read { try ArchiveStore.storedPages(of: statement, in: $0) }
        let asset = try #require(try store.assets(of: statement).first)
        try store.saveText([ExtractedAsset(assetId: asset.id, pages: pages)], for: statement)

        #expect(try store.possibleDuplicates(involving: receipt).first?.decision == false)
    }

    @Test func confirmedIsKeptEvenOutsideTheUsualWindow() throws {
        let (tmp, receipt, _) = try sampleArchive()
        let store = tmp.archive.store
        let pair = try #require(try store.possibleDuplicates(involving: receipt).first)
        try store.decide(pair, isSame: true)
        let answer = try gasInSeptember(store)
        #expect(answer.duplicates.first?.decision == true)
        #expect(answer.totals == [Money(cents: 4410 + 3982)])
    }

    @Test func deletingARecordForgetsItsDecisions() throws {
        let (tmp, receipt, _) = try sampleArchive()
        let store = tmp.archive.store
        try store.decide(try #require(try store.possibleDuplicates(involving: receipt).first), isSame: false)
        try tmp.archive.delete(receipt)
        let left = try store.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM duplicateDecision") }
        #expect(left == 0)
    }
}

@Suite struct CategoryFixes {
    @Test func oneLineKeepsItsOwnCategory() throws {
        let (tmp, _, statement) = try sampleArchive()
        let store = tmp.archive.store
        var line = try #require(try store.transactions(of: statement).first { $0.amountCents == 4410 })
        #expect(line.category == .fuel)
        line.category = .travel
        try store.save(line)
        #expect(try store.transactions(of: statement).first { $0.id == line.id }?.category == .travel)
        #expect(try store.transactions(of: statement).first { $0.id == line.id }?.categoryEdited == true)
    }

    @Test func aMerchantRuleCoversEveryLineAndLaterReads() throws {
        let (tmp, _, statement) = try sampleArchive()
        let store = tmp.archive.store
        let doordash = try store.transactions(of: statement).filter { $0.merchant.lowercased().contains("doordash") }
        let merchant = try #require(doordash.first?.merchant)
        #expect(try store.lineCount(merchant: merchant) == doordash.filter { $0.merchant == merchant }.count)

        try store.setCategory(.groceries, forMerchant: merchant.uppercased())
        #expect(try store.transactions(of: statement).filter { $0.merchant == merchant }.allSatisfy { $0.category == .groceries })

        // Read again: the rule applies to the new rows.
        let pages = try store.db.read { try ArchiveStore.storedPages(of: statement, in: $0) }
        let asset = try #require(try store.assets(of: statement).first)
        try store.saveText([ExtractedAsset(assetId: asset.id, pages: pages)], for: statement)
        #expect(try store.transactions(of: statement).filter { $0.merchant == merchant }.allSatisfy { $0.category == .groceries })
        #expect(try store.merchantCategories()[merchant.lowercased()] == .groceries)
    }

    @Test func aRenamedMerchantFollowsItsRule() throws {
        let (tmp, _, statement) = try sampleArchive()
        let store = tmp.archive.store
        try store.setCategory(.shopping, forMerchant: "Corner Shop")
        var line = try #require(try store.transactions(of: statement).first { $0.amountCents == 4410 })
        line.merchant = "Corner Shop"
        try store.save(line)
        #expect(try store.transactions(of: statement).first { $0.id == line.id }?.category == .shopping)
    }
}

@Suite struct Exporting {
    @Test func everythingIsWrittenAsPlainFiles() throws {
        let (tmp, _, _) = try sampleArchive()
        let out = tmp.directory.appendingPathComponent("out", isDirectory: true)
        let (folder, summary) = try ArchiveExporter.export(tmp.archive, into: out, today: today)

        #expect(folder.lastPathComponent == "Snaplist Export 2026-10-01")
        #expect(summary.records == 2)
        #expect(summary.files == 2)
        let receipts = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Receipts").path).sorted()
        #expect(receipts == ["2026-09-28 Shell.pdf", "2026-09-28 Shell.txt"])

        let data = try Data(contentsOf: folder.appendingPathComponent("Amounts.csv"))
        #expect(data.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        let amounts = String(decoding: data.dropFirst(3), as: UTF8.self)
        #expect(amounts.hasPrefix("Date,Merchant,Amount"))
        #expect(amounts.contains("2026-09-28,Shell,39.82,USD,Purchase,Fuel"))
        #expect(amounts.components(separatedBy: "\r\n").count - 2 == summary.amounts)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Read Me.txt").path))
    }

    @Test func fieldsAndNamesAreEscaped() {
        let data = ArchiveExporter.csv([["a,b", "say \"hi\"", "plain"]])
        #expect(String(decoding: data.dropFirst(3), as: UTF8.self) == "\"a,b\",\"say \"\"hi\"\"\",plain\r\n")
        #expect(ArchiveExporter.safeFileName("Bills: 9/2026") == "Bills- 9-2026")
        #expect(ArchiveExporter.safeFileName("...") == "Untitled")
        #expect(ArchiveExporter.decimal(5) == "0.05")
    }

    @Test func deletingEverythingLeavesNothing() throws {
        let (tmp, _, statement) = try sampleArchive()
        let merchant = try #require(try tmp.archive.store.transactions(of: statement).first?.merchant)
        try tmp.archive.store.setCategory(.other, forMerchant: merchant)
        try tmp.archive.deleteEverything()
        #expect(try tmp.archive.store.records().isEmpty)
        #expect(try tmp.archive.store.merchantCategories().isEmpty)
        #expect(try tmp.folderCount() == 0)
        #expect(try tmp.archive.store.search("shell").isEmpty)
    }
}

@Suite struct Interpreting {
    @Test func aModelsReadingBecomesTheSameQuestion() {
        let read = Interpretation(intent: .spending, categories: [.dining], merchants: ["DoorDash"], period: .month(9, year: nil))
        guard case .spending(let query) = QuestionParser.question(from: read, original: "x", today: today) else {
            Issue.record("not spending"); return
        }
        #expect(query.categories == [.dining])
        #expect(query.merchantTerms == ["doordash"])
        #expect(query.range == DayRange.month(9, of: 2026))
        #expect(query.rangeLabel == "September 2026")

        let lastMonth = Interpretation(intent: .spending, period: .lastMonth)
        if case .spending(let q) = QuestionParser.question(from: lastMonth, original: "x", today: today) {
            #expect(q.range == DayRange.month(9, of: 2026))
        } else { Issue.record("not spending") }

        let november = Interpretation(intent: .spending, period: .month(11, year: nil))
        if case .spending(let q) = QuestionParser.question(from: november, original: "x", today: today) {
            #expect(q.range == DayRange.month(11, of: 2025))
        } else { Issue.record("not spending") }
    }

    @Test func otherKinds() {
        #expect(QuestionParser.question(from: Interpretation(intent: .whereIs, subject: ["the passport"]), original: "x", today: today)
                == .whereIs(terms: ["passport"]))
        #expect(QuestionParser.question(from: Interpretation(intent: .whereIs), original: "where's it", today: today)
                == .search("where's it"))
        #expect(QuestionParser.question(from: Interpretation(intent: .expiry, subject: ["TV"]), original: "x", today: today)
                == .expiry(terms: ["tv"]))
        #expect(QuestionParser.question(from: Interpretation(intent: .spending, period: .month(13, year: nil)),
                                        original: "x", today: today)
                == .spending(SpendingQuery()))
    }
}

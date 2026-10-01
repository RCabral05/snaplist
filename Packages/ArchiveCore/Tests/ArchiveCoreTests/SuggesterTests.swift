import Foundation
import GRDB
import Testing
@testable import ArchiveCore

/// A page from lines given top to bottom, each `(text, height)`.
private func ocr(_ lines: [(String, Double)]) -> RecognizedPage {
    var y = 0.02
    return RecognizedPage(lines: lines.map { text, height in
        defer { y += height + 0.01 }
        return RecognizedLine(text: text, box: PageRect(x: 0.1, y: y, width: 0.8, height: height))
    }, source: .ocr)
}

private func pdf(_ lines: [String]) -> RecognizedPage {
    RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: .pdfText)
}

@Suite struct Suggesting {
    @Test func cvsReceiptFromAPhoneScan() {
        // Roughly what Vision reads from a CVS gift card receipt.
        let page = ocr([
            ("Fast card", 0.012), ("♥CVS pharmacy", 0.03), ("1400 HARTFORD AVENUE", 0.012),
            ("JOHNSTON, RI 02919", 0.012), ("REG#06 TRN#7478 CSHR#2766028 STR#00494", 0.012),
            ("August 5, 2026", 0.012), ("CARD #: XXXXXXXXXXXX0631", 0.015),
            ("YOUR PANERA $25", 0.025), ("CARD/PRODUCT HAS A VALUE OF $25.00", 0.025),
        ])
        #expect(Suggester.suggest([page]) == Suggestion(title: "CVS Pharmacy", kind: .receipt))
    }

    @Test func appleCardStatementPDF() {
        let page = pdf(["Card", "Statement", "Apple Card Customer", "Jul 1 — Jul 31, 2026",
                        "Your July Balance $3,429.57", "Minimum Payment Due $35.00", "Payment Due By Aug 31, 2026"])
        #expect(Suggester.suggest([page]) == Suggestion(title: "Apple Card Statement", kind: .statement))
    }

    @Test func unknownStoreUsesTheTallestLineNearTheTop() {
        let page = ocr([
            ("Welcome!", 0.015), ("BLUE BOTTLE COFFEE", 0.04), ("315 LINDEN ST", 0.012),
            ("LATTE 5.50", 0.012), ("TAX 0.48", 0.012), ("TOTAL 5.98", 0.012), ("VISA 4421", 0.012),
        ])
        #expect(Suggester.suggest([page]) == Suggestion(title: "Blue Bottle Coffee", kind: .receipt))
    }

    @Test func billsAndWarranties() {
        let bill = ocr([("PG&E", 0.04), ("ACCOUNT NUMBER 0123", 0.012), ("TOTAL AMOUNT DUE $160.43", 0.012),
                        ("DUE DATE 09/19/2026", 0.012)])
        #expect(Suggester.suggest([bill]) == Suggestion(title: "PG&E Bill", kind: .bill))

        let warranty = ocr([("SAMSUNG", 0.04), ("LIMITED WARRANTY", 0.02), ("MODEL QN65Q80D", 0.012)])
        #expect(Suggester.suggest([warranty]) == Suggestion(title: "Samsung Warranty", kind: .warranty))
    }

    @Test func namesOnlyMatchWholeWords() {
        let page = ocr([("EGGSHELL PAINT CO", 0.04), ("TOTAL 12.00", 0.012), ("CASH", 0.012)])
        #expect(Suggester.suggest([page]).title == "Eggshell Paint Co")
    }

    @Test func nothingUsableMeansNoSuggestion() {
        let page = ocr([("12/04/2026", 0.03), ("$4.99", 0.03), ("www.example.com", 0.02)])
        #expect(Suggester.suggest([page]) == Suggestion(title: nil, kind: nil))
        #expect(Suggester.suggest([]) == Suggestion(title: nil, kind: nil))
    }

    @Test func casing() {
        #expect(Suggester.titleCased("TRADER JOE'S MARKET") == "Trader Joe's Market")
        #expect(Suggester.titleCased("CVS pharmacy") == "CVS Pharmacy")
        #expect(Suggester.clean("  **♥CVS pharmacy*  ") == "CVS pharmacy")
    }
}

@Suite struct ApplyingSuggestions {
    func ingest(_ archive: Archive, title: String, source: NameSource, kind: RecordKind = .document,
                page: RecognizedPage) async throws -> ArchiveCore.Record {
        let item = ImportItem(type: .image, source: .data(Data([1])), fileExtension: "jpg")
        let record = try archive.add(kind: kind, title: title, nameSource: source, items: [item])
        let asset = try #require(try archive.store.assets(of: record.id).first)
        try archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: [page])], for: record.id)
        return try #require(try archive.store.record(record.id))
    }

    let receipt = ocr([("SHELL", 0.04), ("FUEL TOTAL $39.82", 0.012), ("VISA 4421", 0.012)])

    @Test func placeholderNamesAreReplacedAndIndexed() async throws {
        let tmp = try TemporaryArchive()
        let record = try await ingest(tmp.archive, title: "Scan Sep 30", source: .automatic, page: receipt)

        #expect(record.title == "Shell")
        #expect(record.kind == .receipt)
        #expect(try tmp.archive.store.search("shell").first?.record.title == "Shell")
        #expect(try tmp.archive.store.search("scan").isEmpty)
    }

    @Test func fileNamesStayButGetACategory() async throws {
        let tmp = try TemporaryArchive()
        let record = try await ingest(tmp.archive, title: "gas-sept", source: .file, page: receipt)
        #expect(record.title == "gas-sept")
        #expect(record.kind == .receipt)
    }

    @Test func whatAPersonChoseIsNeverChanged() async throws {
        let tmp = try TemporaryArchive()
        let mine = try await ingest(tmp.archive, title: "Road trip gas", source: .person, kind: .other, page: receipt)
        #expect(mine.title == "Road trip gas")
        #expect(mine.kind == .other)

        let filed = try await ingest(tmp.archive, title: "Scan", source: .automatic, kind: .bill, page: receipt)
        #expect(filed.title == "Shell")
        #expect(filed.kind == .bill)
    }

    @Test func editingMakesARecordThePersons() async throws {
        let tmp = try TemporaryArchive()
        var record = try await ingest(tmp.archive, title: "Scan", source: .automatic, page: receipt)
        record.title = "Fuel"
        try tmp.archive.store.update(record)

        #expect(try tmp.archive.store.record(record.id)?.nameSource == .person)
        #expect(try tmp.archive.store.refreshSuggestions() == 0)
        #expect(try tmp.archive.store.record(record.id)?.title == "Fuel")
    }

    @Test func refreshNamesRecordsReadBeforeSuggestionsExisted() async throws {
        let tmp = try TemporaryArchive()
        let record = try await ingest(tmp.archive, title: "Scan", source: .automatic, page: receipt)
        // Simulate an older record: placeholder name and default kind, text already stored.
        try await tmp.archive.store.db.write { db in
            try db.execute(sql: "UPDATE record SET title = 'Scan Sep 30', kind = 'document' WHERE id = ?",
                           arguments: [record.id])
        }

        #expect(try tmp.archive.store.refreshSuggestions() == 1)
        let refreshed = try #require(try tmp.archive.store.record(record.id))
        #expect(refreshed.title == "Shell")
        #expect(refreshed.kind == .receipt)
        #expect(try tmp.archive.store.refreshSuggestions() == 0)
    }

    @Test func theMigrationMarksOldPlaceholdersAutomatic() throws {
        // A database as the first release left it, before nameSource existed.
        let queue = try DatabaseQueue()
        try ArchiveStore.migrator.migrate(queue, upTo: "v1")
        try queue.write { db in
            for (id, title) in [(1, "Scan Sep 30, 2026 at 10:12 PM"), (2, "Photo Oct 1"), (3, "Apple Card Statement")] {
                try db.execute(
                    sql: "INSERT INTO record (id, kind, title, createdAt, status) VALUES (?, 'document', ?, '2026-09-30', 'ready')",
                    arguments: [Data([UInt8(id)]), title])
            }
        }

        let store = try ArchiveStore(db: queue)
        let sources = try store.db.read {
            try String.fetchAll($0, sql: "SELECT nameSource FROM record ORDER BY id")
        }
        #expect(sources == ["automatic", "automatic", "person"])
    }
}

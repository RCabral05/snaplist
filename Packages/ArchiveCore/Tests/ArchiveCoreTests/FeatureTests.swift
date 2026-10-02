import Foundation
import Testing
@testable import ArchiveCore

private func add(_ tmp: TemporaryArchive, kind: RecordKind = .document, title: String = "Scan",
                 source: TextSource = .pdfText, type: AssetType = .pdf, lines: [String]) throws -> UUID {
    let record = try tmp.archive.add(kind: kind, title: title, nameSource: kind == .document ? .automatic : .person,
                                     items: [ImportItem(type: type, source: .data(Data([1])), fileExtension: type == .csv ? "csv" : "pdf")])
    let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
    try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: [
        RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: source),
    ])], for: record.id)
    return record.id
}

/// Apple Card's export, as its columns come.
private let appleCardCSV = [
    "Transaction Date,Clearing Date,Description,Merchant,Category,Type,Amount (USD),Purchased By",
    "07/28/2026,07/29/2026,\"DOORDASH*WENDYS, SAN FRANCISCO CA\",DoorDash,Restaurants,Purchase,18.20,Ryan",
    "07/22/2026,07/23/2026,SHELL OIL 57442,Shell,Gas,Purchase,51.00,Ryan",
    "07/20/2026,07/20/2026,ACH DEPOSIT INTERNET TRANSFER,Ach Deposit Internet Transfer,Payment,Payment,-300.00,Ryan",
    "07/18/2026,07/19/2026,AMAZON MKTPL,Amazon,Shopping,Credit,-33.10,Ryan",
    "07/15/2026,07/16/2026,MONTHLY INSTALLMENT,Apple,Other,Installment,41.62,Ryan",
]

@Suite struct CSVImports {
    @Test func appleCardExport() throws {
        let tmp = try TemporaryArchive()
        let id = try add(tmp, kind: .statement, title: "Apple Card July", source: .file, type: .csv, lines: appleCardCSV)
        let lines = try tmp.archive.store.transactions(of: id)
        #expect(lines.count == 5)
        let doordash = try #require(lines.first { $0.merchant == "DoorDash" })
        #expect(doordash.amountCents == 1820)
        #expect(doordash.kind == .purchase)
        #expect(doordash.category == .dining)
        #expect(doordash.memo == "DOORDASH*WENDYS, SAN FRANCISCO CA")
        #expect(doordash.linePosition == 1)
        #expect(lines.first { $0.merchant == "Shell" }?.category == .fuel)
        #expect(lines.first { $0.amountCents == 30000 }?.kind == .payment)
        #expect(lines.first { $0.amountCents == 3310 }?.kind == .refund)
        #expect(try tmp.archive.store.record(id)?.documentDate == Day(year: 2026, month: 7, day: 28))

        let july = try tmp.archive.store.answer(SpendingQuery(range: DayRange.month(7, of: 2026), rangeLabel: "July 2026"))
        #expect(july.totals == [Money(cents: 1820 + 5100 - 3310 + 4162)])
    }

    @Test func bankExportWithNegativePurchasesAndISODates() throws {
        let tmp = try TemporaryArchive()
        let id = try add(tmp, kind: .statement, source: .file, type: .csv, lines: [
            "Date,Description,Amount",
            "2026-08-02,TRADER JOE'S #231,-21.72",
            "2026-08-03,NETFLIX.COM,-15.49",
            "2026-08-05,PAYROLL DEPOSIT,2500.00",
        ])
        let lines = try tmp.archive.store.transactions(of: id)
        #expect(lines.map(\.kind) == [.purchase, .purchase, .refund])
        #expect(lines.first?.amountCents == 2172)
        #expect(lines.first?.date == Day(year: 2026, month: 8, day: 2))
    }

    @Test func debitAndCreditColumns() throws {
        let tmp = try TemporaryArchive()
        let id = try add(tmp, kind: .statement, source: .file, type: .csv, lines: [
            "Posted Date,Payee,Debit,Credit",
            "08/02/2026,COSTCO WHSE,72.65,",
            "08/09/2026,COSTCO WHSE,,10.00",
        ])
        #expect(try tmp.archive.store.transactions(of: id).map(\.kind) == [.purchase, .refund])
    }

    @Test func notATransactionsFileIsReadAsText() {
        #expect(!CSVStatement.looksLikeCSV([RecognizedPage(lines: [RecognizedLine(text: "Name,Phone")], source: .file)]))
        #expect(CSVStatement.fields("a,\"b, c\",\"say \"\"hi\"\"\",") == ["a", "b, c", "say \"hi\"", ""])
        #expect(CSVStatement.cents("(1,234.5)") == -123450)
        #expect(CSVStatement.cents("$12") == 1200)
    }

    @Test func theSameChargeOnACSVAndAPDFCountsOnce() throws {
        let tmp = try TemporaryArchive()
        _ = try add(tmp, lines: ["CHASE", "Freedom Visa Statement", "Statement period 07/01/2026 - 07/31/2026",
                                 "07/22  SHELL OIL 57442  51.00"])
        _ = try add(tmp, kind: .statement, source: .file, type: .csv, lines: appleCardCSV)
        let gas = try tmp.archive.store.answer(SpendingQuery(categories: [.fuel], range: DayRange.month(7, of: 2026), rangeLabel: "July 2026"))
        #expect(gas.totals == [Money(cents: 5100)])
        #expect(gas.duplicates.count == 1)
    }
}

@Suite struct ReturnWindows {
    let purchased = Day(year: 2026, month: 9, day: 28)!

    func rows(_ lines: String...) -> [TextRow] {
        lines.enumerated().map { TextRow(text: $1, pagePosition: 0, linePosition: $0) }
    }

    @Test func policiesPrintedOnReceipts() {
        #expect(ArchiveStore.returnDeadline(in: rows("TARGET", "Returns accepted within 90 days with receipt"), purchased: purchased)
                == purchased.adding(days: 90))
        #expect(ArchiveStore.returnDeadline(in: rows("30-DAY RETURN POLICY"), purchased: purchased) == purchased.adding(days: 30))
        #expect(ArchiveStore.returnDeadline(in: rows("09/28/2026", "RETURN BY 10/28/2026"), purchased: purchased)
                == Day(year: 2026, month: 10, day: 28))
        #expect(ArchiveStore.returnDeadline(in: rows("THANK YOU", "TOTAL 39.82"), purchased: purchased) == nil)
        #expect(ArchiveStore.returnDeadline(in: rows("All sales final. No returns."), purchased: purchased) == nil)
    }

    @Test func upcomingIncludesOpenReturnWindows() throws {
        let tmp = try TemporaryArchive()
        _ = try add(tmp, kind: .receipt, title: "Best Buy", lines: ["BEST BUY", "09/28/2026", "TOTAL $199.99", "Return within 15 days of purchase"])
        _ = try add(tmp, lines: ["TARGET", "08/01/2026", "TOTAL $20.00", "Return within 30 days"])
        let dates = try tmp.archive.store.upcomingDates(from: Day(year: 2026, month: 10, day: 1)!)
        #expect(dates.map(\.kind) == [.returnBy])
        #expect(dates.first?.day == Day(year: 2026, month: 10, day: 13))
        #expect(dates.first?.amount == Money(cents: 19999))
    }
}

@Suite struct Budgets {
    @Test func limitsAgainstTheMonth() throws {
        let tmp = try TemporaryArchive()
        _ = try add(tmp, kind: .statement, source: .file, type: .csv, lines: appleCardCSV)
        let store = tmp.archive.store
        try store.setBudget(5000, for: .dining)
        try store.setBudget(200_000, for: nil)
        try store.setBudget(10000, for: .fuel)
        try store.setBudget(0, for: .fuel)
        #expect(try store.budgets().map(\.category) == [nil, .dining])

        let july = try #require(DayRange.month(7, of: 2026))
        let status = try store.budgetStatus(in: july)
        let dining = try #require(status.first { $0.budget.category == .dining })
        #expect(dining.spentCents == 1820)
        #expect(abs(dining.fraction - 0.364) < 0.001)
        #expect(status.first { $0.budget.category == nil }?.spentCents == Int64(1820 + 5100 - 3310 + 4162))
    }
}

@Suite struct Inventory {
    @Test func belongingsWithSuggestions() throws {
        let tmp = try TemporaryArchive()
        let tv = try add(tmp, kind: .receipt, title: "Samsung TV", lines: ["BEST BUY", "03/01/2026", "QN65Q80D S/N: 0ABC1234XYZ",
                                                                            "TOTAL $1,299.99"])
        let store = tmp.archive.store
        var item = try #require(try store.suggestedBelonging(for: tv))
        #expect(item.name == "Samsung TV")
        #expect(item.valueCents == 129999)
        #expect(item.serialNumber == "0ABC1234XYZ")
        #expect(item.purchased == Day(year: 2026, month: 3, day: 1))

        item.room = "Living room"
        try store.save(item)
        #expect(try store.belongings().map(\.room) == ["Living room"])
        #expect(try store.inventorySummary().totalCents == 129999)

        let out = tmp.directory.appendingPathComponent("out")
        let folder = try ArchiveExporter.exportInventory(tmp.archive, into: out)
        let csv = String(decoding: try Data(contentsOf: folder.appendingPathComponent("Inventory.csv")).dropFirst(3), as: UTF8.self)
        #expect(csv.contains("Samsung TV,Living room,1299.99,USD,0ABC1234XYZ,2026-03-01"))

        try tmp.archive.delete(tv)
        #expect(try store.belongings().isEmpty)
    }
}

@Suite struct TaxReports {
    @Test func taggedRecordsByPurpose() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        let laptop = try add(tmp, kind: .receipt, title: "Laptop", lines: ["APPLE STORE", "03/02/2026", "TOTAL $999.00"])
        let doctor = try add(tmp, kind: .bill, title: "Dr. Lee", lines: ["CITY CLINIC", "STATEMENT DATE 04/10/2026", "AMOUNT DUE $120.00"])
        let old = try add(tmp, kind: .receipt, title: "Old desk", lines: ["IKEA", "05/05/2025", "TOTAL $150.00"])
        try store.addTag("Business", kind: .tax, to: laptop)
        try store.addTag("Medical", kind: .tax, to: doctor)
        try store.addTag("Business", kind: .tax, to: old)

        #expect(try store.taxYears() == [2026, 2025])
        let report = try store.taxReport(year: 2026)
        #expect(report.groups.map(\.purpose) == ["Business", "Medical"])
        #expect(report.groups[0].totalCents == 99900)
        #expect(report.totalCents == 99900 + 12000)

        let folder = try ArchiveExporter.exportTaxReport(tmp.archive, year: 2026, into: tmp.directory.appendingPathComponent("out"))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Business/2026-03-02 Laptop.pdf").path))
        let summary = String(decoding: try Data(contentsOf: folder.appendingPathComponent("Summary.csv")).dropFirst(3), as: UTF8.self)
        #expect(summary.contains("Medical,2026-04-10,Dr. Lee,Bill,120.00,USD"))
    }
}

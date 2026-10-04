import Foundation
import Testing
@testable import ArchiveCore

private func add(_ tmp: TemporaryArchive, _ pages: [[String]]) throws -> UUID {
    let record = try tmp.archive.add(kind: .document, title: "Scan", nameSource: .automatic,
                                     items: [ImportItem(type: .pdf, source: .data(Data([1])), fileExtension: "pdf")])
    let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
    try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: pages.map { lines in
        RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: .pdfText)
    })], for: record.id)
    return record.id
}

@Suite struct Redaction {
    @Test func privateDetailsAreFound() {
        let hidden: [(String, Redactor.Reason)] = [
            ("VISA ************4421", .card), ("4111 1111 1111 1111", .card), ("MASTERCARD XXXX8812 APPROVED", .card),
            ("444 Example Ln.", .address), ("Warwick, RI 02886", .address), ("1709 Automation Pkwy", .address),
            ("401-555-0199", .phone), ("(408) 555-0144", .phone), ("Account number 0000-0101-22", .account),
            ("Passport No. X00000000", .idNumber), ("DOB 01/02/1990", .birthDate), ("someone@example.com", .email),
            ("SSN 000-00-0000", .idNumber),
        ]
        for (text, reason) in hidden {
            #expect(Redactor.reason(for: text) == reason, "\(text)")
        }
        // What the copy is for stays readable.
        for text in ["COSTCO WHOLESALE", "ORGANIC EGGS 24  8.79", "TOTAL $72.65", "09/25/2026 17:42", "Total Items: 7",
                     "SAN JOSE #423", "Order: 00000000", "Statement period 09/01/2026 - 09/30/2026", "UNLEADED 10.214 GAL"] {
            #expect(Redactor.reason(for: text) == nil, "\(text)")
        }
        let page = RecognizedPage(lines: ["TARGET", "12 Park Ave", "TOTAL 20.00", "VISA ****4421"].map { RecognizedLine(text: $0) },
                                  source: .ocr)
        #expect(Redactor.privateLines(page).map(\.index) == [1, 3])
    }
}

@Suite struct CarServices {
    @Test func historyMileageAndTheNextOilChange() throws {
        let tmp = try TemporaryArchive()
        _ = try add(tmp, [["JIFFY LUBE #2291", "Service Invoice", "02/01/2026", "Vehicle: 2019 Honda Civic", "Mileage: 40,000",
                           "Synthetic oil change  72.99", "TOTAL $72.99", "VISA"]])
        _ = try add(tmp, [["CITY TIRE & AUTO", "Repair Order 5521", "05/10/2026", "Odometer 42,600", "Mount and balance 4 tires  480.00",
                           "Alignment  89.99", "TOTAL $569.99", "VISA"]])
        _ = try add(tmp, [["JIFFY LUBE #2291", "Service Invoice", "08/01/2026", "Vehicle: 2019 Honda Civic", "Miles In 45,100",
                           "Full synthetic oil change  79.99", "Tire rotation  10.00", "TOTAL $89.99", "VISA"]])
        // Not the car's battery.
        _ = try add(tmp, [["CVS pharmacy", "09/01/2026", "AA BATTERIES 8PK  9.99", "TOTAL 9.99", "VISA"]])

        let car = try #require(try tmp.archive.store.carSummary())
        #expect(car.services.count == 3)
        #expect(car.services.map(\.kinds) == [[.oilChange, .tireRotation], [.tires, .alignment], [.oilChange]])
        #expect(car.services.map(\.mileage) == [45_100, 42_600, 40_000])
        #expect(car.latestMileage?.miles == 45_100)
        let rate = try #require(car.milesPerDay)
        #expect(abs(rate - 5_100.0 / 181.0) < 0.01)
        #expect(car.lastOilChange?.day == Day(year: 2026, month: 8, day: 1))
        #expect(car.nextOilChangeMiles == 50_100)
        // 5,000 miles at about 28 a day comes before six months.
        let due = try #require(car.nextOilChange)
        #expect(due < Day(year: 2027, month: 2, day: 1)!)
        #expect(due > Day(year: 2027, month: 1, day: 15)!)
        #expect(car.services.first?.amount == Money(cents: 8999))
        #expect(car.estimatedMileage(on: Day(year: 2026, month: 10, day: 1)!)! > 45_100)
    }

    @Test func noCarNoSummary() throws {
        let tmp = try TemporaryArchive()
        _ = try add(tmp, [["CVS pharmacy", "09/01/2026", "AA BATTERIES 8PK  9.99", "TOTAL 9.99", "VISA"]])
        #expect(try tmp.archive.store.carSummary() == nil)
    }
}

@Suite struct Subscriptions {
    func statements(_ tmp: TemporaryArchive) throws {
        for month in 6...8 {
            _ = try add(tmp, [["CHASE", "Freedom Visa Statement", String(format: "Statement period %02d/01/2026 - %02d/28/2026", month, month),
                               "New balance $50.00"],
                              [String(format: "%02d/03  NETFLIX.COM  15.49", month), String(format: "%02d/05  DOORDASH*DASHPASS  9.99", month)]])
        }
    }

    @Test func foundTrialsRemindersAndCancelling() throws {
        let tmp = try TemporaryArchive()
        try statements(tmp)
        let store = tmp.archive.store
        var list = try store.subscriptions()
        #expect(list.map(\.name).sorted() == ["DoorDash", "Netflix"])
        let netflix = try #require(list.first { $0.name == "Netflix" })
        #expect(netflix.nextCharge == Day(year: 2026, month: 9, day: 3))
        #expect(netflix.yearlyCents == 1549 * 12)
        #expect(!netflix.remind)

        try store.addTrial(name: "Example Plus", priceCents: 999, cadence: .monthly, ends: Day(year: 2026, month: 9, day: 1)!)
        var cancelled = netflix
        cancelled.cancelledOn = Day(year: 2026, month: 8, day: 20)
        try store.save(cancelled)
        list = try store.subscriptions()
        // The trial charges first; cancelled ones go last.
        #expect(list.map(\.name) == ["Example Plus", "DoorDash", "Netflix"])
        #expect(list[0].remind && list[0].charge == nil && list[0].nextCharge == Day(year: 2026, month: 9, day: 1))
        #expect(list[2].nextCharge == nil)
        #expect(!list[2].chargedAfterCancel)

        // Netflix charges again after being cancelled: that's worth saying.
        _ = try add(tmp, [["CHASE", "Freedom Visa Statement", "Statement period 09/01/2026 - 09/28/2026", "New balance $15.49"],
                          ["09/03  NETFLIX.COM  15.49"]])
        #expect(try store.subscriptions().first { $0.name == "Netflix" }?.chargedAfterCancel == true)
    }
}

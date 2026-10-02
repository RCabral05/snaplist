import Foundation
import Testing
@testable import ArchiveCore

/// A year of made-up paperwork for one made-up household, read through the
/// same pipeline as a real import: receipts in a dozen printed styles,
/// card statements as PDFs and CSVs, utility and phone bills, IDs and
/// policies, warranties, manuals, voice notes and screenshots.
///
/// Alongside it, a ledger of what really happened: every purchase once,
/// whether it shows up on a receipt, a statement, or both. The corpus tests
/// check that Snaplist's answers agree with the ledger. Nothing here is real
/// data; names, numbers and accounts are invented.
struct Corpus {
    /// One real purchase, however many records show it.
    struct Purchase {
        var day: Day
        var cents: Int64
        var category: SpendCategory
        var merchant: String
        /// Money back rather than out.
        var isRefund = false
    }

    struct ExpectedRecord {
        var id: UUID
        var kind: RecordKind?
        var title: String?
        /// A receipt's total or a bill's amount due.
        var totalCents: Int64?
        var category: SpendCategory?
        var day: Day?
        var label: String
    }

    let tmp: TemporaryArchive
    var store: ArchiveStore { tmp.archive.store }
    var ledger: [Purchase] = []
    var expected: [ExpectedRecord] = []
    /// Named records the tests look up directly.
    var named: [String: UUID] = [:]

    static let today = Day(year: 2026, month: 10, day: 1)!
    /// October 2025 to September 2026.
    static let months: [(year: Int, month: Int)] = (0..<12).map { offset in
        let index = 9 + offset
        return (2025 + index / 12, index % 12 + 1)
    }

    // MARK: Building

    static func build(seed: UInt64 = 20261001) throws -> Corpus {
        var corpus = Corpus(tmp: try TemporaryArchive())
        var rng = SeededRandom(seed: seed)
        try corpus.addReceipts(&rng)
        try corpus.addBills()
        try corpus.addStatements(&rng)
        try corpus.addDocuments()
        try corpus.addNotesAndScreenshots()
        return corpus
    }

    @discardableResult
    mutating func ingest(_ pages: [RecognizedPage], type: AssetType = .pdf, label: String) throws -> UUID {
        let ext = switch type {
        case .csv: "csv"
        case .image: "jpg"
        case .audio: "m4a"
        default: "pdf"
        }
        // CSVs come in the way the app imports them: a statement, named for the file.
        let record = type == .csv
            ? try tmp.archive.add(kind: .statement, title: "Transactions", nameSource: .file,
                                  items: [ImportItem(type: type, source: .data(Data([1])), fileExtension: ext)])
            : try tmp.archive.add(kind: .document, title: "Scan", nameSource: .automatic,
                                  items: [ImportItem(type: type, source: .data(Data([1])), fileExtension: ext)])
        let asset = try #require(try store.assets(of: record.id).first)
        try store.saveText([ExtractedAsset(assetId: asset.id, pages: pages)], for: record.id)
        named[label] = record.id
        return record.id
    }

    static func pdf(_ lines: [String]) -> RecognizedPage {
        RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: .pdfText)
    }

    static func ocr(_ lines: [String]) -> RecognizedPage {
        RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: .ocr)
    }

    static func money(_ cents: Int64) -> String {
        String(format: "%d.%02d", cents / 100, cents % 100)
    }

    static func moneyWithCommas(_ cents: Int64) -> String {
        let whole = cents / 100
        let grouped = whole >= 1000 ? "\(whole / 1000),\(String(format: "%03d", whole % 1000))" : "\(whole)"
        return grouped + String(format: ".%02d", cents % 100)
    }

    // MARK: Receipts

    struct Store {
        var printed: [String]
        var title: String
        var category: SpendCategory
        /// How a card statement prints it.
        var statementMemo: String
        var items: [(String, ClosedRange<Int>)]
        var taxed: Bool = true
    }

    static let stores: [Store] = [
        Store(printed: ["COSTCO WHOLESALE", "SAN JOSE #423", "1709 AUTOMATION PKWY"], title: "Costco", category: .groceries,
              statementMemo: "COSTCO WHSE #0423", items: [
                ("KS PAPER TOWEL", 1899...2399), ("ORGANIC EGGS 24", 699...899), ("ROTISSERIE CHKN", 499...499),
                ("OLIVE OIL 2L", 1399...1699), ("AA BATTERIES 48", 1599...1899), ("KS ALMOND MILK", 899...999),
                ("BLUEBERRIES 18OZ", 549...699), ("GROUND COFFEE 3LB", 1499...1899)]),
        Store(printed: ["TRADER JOE'S", "#231 SAN JOSE CA", "(408) 555-0144"], title: "Trader Joe's", category: .groceries,
              statementMemo: "TRADER JOE'S #231", items: [
                ("BANANAS", 23...29), ("EGGS DOZEN", 349...429), ("MANDARIN CHICKEN", 499...549),
                ("GREEK YOGURT", 449...499), ("SOURDOUGH", 399...399), ("CHEDDAR", 499...599)], taxed: false),
        Store(printed: ["WHOLE FOODS MARKET", "777 THE ALAMEDA"], title: "Whole Foods", category: .groceries,
              statementMemo: "WHOLEFDS SJC 10231", items: [
                ("ORGANIC SPINACH", 399...499), ("SALMON FILLET", 1299...1699), ("AVOCADO HASS", 199...249),
                ("KOMBUCHA", 349...399)], taxed: false),
        Store(printed: ["TARGET", "SAN JOSE NORTH - 408-555-0110"], title: "Target", category: .shopping,
              statementMemo: "TARGET 00012345", items: [
                ("TIDE PODS 81CT", 2199...2499), ("BATH TOWEL", 999...1499), ("HDMI CABLE 6FT", 1299...1299),
                ("STORAGE BIN", 799...1199), ("PHONE CHARGER", 1999...2499)]),
        Store(printed: ["CVS pharmacy", "STORE 9921"], title: "CVS Pharmacy", category: .pharmacy,
              statementMemo: "CVS/PHARMACY #09921", items: [
                ("ADVIL 100CT", 1199...1399), ("BAND-AID", 499...599), ("VITAMIN D3", 899...1099), ("TOOTHPASTE", 399...549)]),
        Store(printed: ["HOME DEPOT", "#1861 SAN JOSE"], title: "Home Depot", category: .shopping,
              statementMemo: "THE HOME DEPOT #1861", items: [
                ("FURNACE FILTER 20X25", 1999...2499), ("LED BULB 4PK", 999...1299), ("PAINTERS TAPE", 699...799),
                ("WOOD SCREWS", 599...899)]),
        Store(printed: ["STARBUCKS", "Store #10442"], title: "Starbucks", category: .dining,
              statementMemo: "STARBUCKS STORE 10442", items: [
                ("GRANDE LATTE", 545...595), ("CROISSANT", 375...395), ("COLD BREW", 495...525)]),
        Store(printed: ["MARIO'S PIZZERIA", "41 ELM STREET"], title: "Mario's Pizzeria", category: .dining,
              statementMemo: "MARIOS PIZZERIA", items: [
                ("LARGE MARGHERITA", 1899...2199), ("GARLIC KNOTS", 699...699), ("CAESAR SALAD", 1099...1199)]),
        Store(printed: ["GREEN LEAF CAFE", "12 PARK AVE"], title: "Green Leaf Cafe", category: .dining,
              statementMemo: "SQ *GREEN LEAF CAFE", items: [
                ("AVOCADO TOAST", 1250...1350), ("OAT LATTE", 550...595)]),
    ]

    /// Ways a receipt prints its date.
    static func printedDate(_ day: Day, style: Int) -> String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        switch style % 5 {
        case 0: return String(format: "%02d/%02d/%04d %02d:%02d", day.month, day.day, day.year, 9 + day.day % 10, day.day * 2 % 60)
        case 1: return String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
        case 2: return "\(names[day.month - 1]) \(day.day), \(day.year)"
        case 3: return String(format: "%02d/%02d/%02d", day.month, day.day, day.year % 100)
        default: return String(format: "DATE: %02d/%02d/%04d", day.month, day.day, day.year)
        }
    }

    mutating func addReceipts(_ rng: inout SeededRandom) throws {
        var count = 0
        for (year, month) in Self.months {
            // Groceries, a coffee or two, a dinner, a pharmacy run, a Target
            // trip and sometimes Home Depot, every month.
            let plan = [0, 1, 2, 3, 4, 5, 6, 6, 7, 8] + (month % 3 == 0 ? [5] : [])
            for (visit, storeIndex) in plan.enumerated() {
                let store = Self.stores[storeIndex]
                let day = Day(year: year, month: month, day: 2 + (visit * 3 + rng.int(0...2)) % 26)!
                let itemCount = min(store.items.count, rng.int(1...4))
                var picked = store.items
                rng.shuffle(&picked)
                let lines = picked.prefix(itemCount).map { ($0.0, Int64(rng.int($0.1))) }
                let subtotal = lines.reduce(0) { $0 + $1.1 }
                let tax = store.taxed ? subtotal * 9375 / 100_000 : 0
                let total = subtotal + tax
                let style = rng.int(0...99)
                var text = store.printed
                text.append(Self.printedDate(day, style: style))
                for (name, cents) in lines {
                    text.append(name + String(repeating: " ", count: max(2, 22 - name.count)) + Self.money(cents))
                }
                text.append("SUBTOTAL            " + Self.money(subtotal))
                if store.taxed { text.append("TAX                 " + Self.money(tax)) }
                switch style % 4 {
                case 0: text.append("TOTAL               " + Self.money(total))
                case 1: text.append("TOTAL $" + Self.money(total))
                case 2: text.append("Total: $" + Self.money(total))
                default: text.append("GRAND TOTAL  " + Self.money(total))
                }
                let paidCash = style % 7 == 3
                if paidCash {
                    let tendered = (total / 2000 + 1) * 2000
                    text.append("CASH                " + Self.money(tendered))
                    text.append("CHANGE DUE          " + Self.money(tendered - total))
                } else {
                    text.append(style % 2 == 0 ? "VISA ************4421" : "MASTERCARD XXXX8812 APPROVED")
                    text.append("AUTH CODE 0\(100 + count % 900)")
                }
                text.append(style % 3 == 0 ? "THANK YOU FOR SHOPPING" : "Returns within 30 days with receipt")

                let label = "receipt \(count)"
                let id = try ingest([style % 2 == 0 ? Self.ocr(text) : Self.pdf(text)], type: .image, label: label)
                expected.append(ExpectedRecord(id: id, kind: .receipt, title: store.title, totalCents: total,
                                               category: store.category, day: day, label: label))
                ledger.append(Purchase(day: day, cents: total, category: store.category, merchant: store.title))
                if !paidCash, style % 2 == 0 {
                    cardPurchases.append(CardLine(day: day.adding(days: rng.int(0...2)), memo: store.statementMemo,
                                                  cents: total, alreadyCounted: true, category: store.category))
                }
                count += 1
            }

            // Gas, twice a month, on a pump receipt.
            for fill in 0..<2 {
                let day = Day(year: year, month: month, day: 5 + fill * 13 + rng.int(0...4))!
                let tenths = Int64(rng.int(95...135))
                let pricePerGallon = Int64(rng.int(3599...4299))
                let total = tenths * pricePerGallon / 1000
                let brand = fill == 0 ? ("SHELL", "Shell", "SHELL OIL 57442") : ("CHEVRON", "Chevron", "CHEVRON 0209843")
                let text = [brand.0, "PUMP 0\(fill + 3)", Self.printedDate(day, style: fill), "UNLEADED \(tenths / 10).\(tenths % 10)00 GAL",
                            "PRICE/GAL $\(pricePerGallon / 1000).\(pricePerGallon % 1000)", "FUEL TOTAL $" + Self.money(total),
                            "VISA ************4421", "APPROVED"]
                let label = "fuel \(year)-\(month)-\(fill)"
                let id = try ingest([Self.ocr(text)], type: .image, label: label)
                expected.append(ExpectedRecord(id: id, kind: .receipt, title: brand.1, totalCents: total, category: .fuel,
                                               day: day, label: label))
                ledger.append(Purchase(day: day, cents: total, category: .fuel, merchant: brand.1))
                cardPurchases.append(CardLine(day: day.adding(days: 1), memo: brand.2, cents: total, alreadyCounted: true,
                                              category: .fuel))
            }
        }

        // One-offs that matter later: a TV with a warranty and a manual, an
        // oil change, a vet visit, a hotel stay.
        let tv = ["BEST BUY", "Store 0187", "03/14/2026", "SAMSUNG QN65Q80D TV  1,299.99", "S/N: 0ABC1234XYZ",
                  "GEEK SQUAD PROTECTION  199.99", "SUBTOTAL  1,499.98", "TAX  140.62", "TOTAL $1,640.60",
                  "VISA ************4421", "Return within 15 days of purchase"]
        let tvId = try ingest([Self.pdf(tv)], label: "tv receipt")
        expected.append(ExpectedRecord(id: tvId, kind: .receipt, title: "Best Buy", totalCents: 164060, category: .shopping,
                                       day: Day(year: 2026, month: 3, day: 14), label: "tv receipt"))
        ledger.append(Purchase(day: Day(year: 2026, month: 3, day: 14)!, cents: 164060, category: .shopping, merchant: "Best Buy"))
        cardPurchases.append(CardLine(day: Day(year: 2026, month: 3, day: 15)!, memo: "BEST BUY 00001875", cents: 164060,
                                      alreadyCounted: true, category: .shopping))

        for (index, day) in [Day(year: 2026, month: 2, day: 7)!, Day(year: 2026, month: 8, day: 12)!].enumerated() {
            let cents: Int64 = index == 0 ? 7499 : 8299
            let text = ["JIFFY LUBE #2291", "Service Invoice", Self.printedDate(day, style: 0), "Vehicle: 2019 Honda Civic",
                        "Synthetic oil change  " + Self.money(cents - 1000), "Tire rotation  10.00", "TOTAL $" + Self.money(cents),
                        "VISA ************4421"]
            let id = try ingest([Self.pdf(text)], label: "oil change \(index)")
            expected.append(ExpectedRecord(id: id, kind: .receipt, title: nil, totalCents: cents, category: nil, day: day,
                                           label: "oil change \(index)"))
            ledger.append(Purchase(day: day, cents: cents, category: SpendCategories.classify(merchant: "Jiffy Lube", memo: ""),
                                   merchant: "Jiffy Lube"))
        }

        let vet = ["BAYSIDE ANIMAL HOSPITAL", "Patient: Biscuit (canine)", "05/20/2026", "Annual exam  65.00",
                   "Rabies vaccine  28.00", "TOTAL  93.00", "VISA ************4421", "Thank you"]
        let vetId = try ingest([Self.pdf(vet)], label: "vet")
        expected.append(ExpectedRecord(id: vetId, kind: .receipt, title: "Bayside Animal Hospital", totalCents: 9300,
                                       category: .other, day: Day(year: 2026, month: 5, day: 20), label: "vet"))
        ledger.append(Purchase(day: Day(year: 2026, month: 5, day: 20)!, cents: 9300, category: .other, merchant: "Bayside"))
    }

    // MARK: Statements

    struct CardLine {
        var day: Day
        var memo: String
        var cents: Int64
        /// Already in the ledger through a receipt.
        var alreadyCounted: Bool
        var category: SpendCategory
        var isRefund = false
        var isPayment = false
    }

    var cardPurchases: [CardLine] = []

    mutating func addStatements(_ rng: inout SeededRandom) throws {
        // Things only the card knows about.
        for (year, month) in Self.months {
            let netflix: Int64 = (year, month) >= (2026, 8) ? 1799 : 1549
            var extra: [CardLine] = [
                CardLine(day: Day(year: year, month: month, day: 3)!, memo: "NETFLIX.COM", cents: netflix,
                         alreadyCounted: false, category: .subscriptions),
                CardLine(day: Day(year: year, month: month, day: 9)!, memo: "SPOTIFY USA", cents: 1199,
                         alreadyCounted: false, category: .subscriptions),
                CardLine(day: Day(year: year, month: month, day: 11)!, memo: "DOORDASH*THAI BASIL", cents: Int64(rng.int(2400...4100)),
                         alreadyCounted: false, category: .dining),
                CardLine(day: Day(year: year, month: month, day: 19)!, memo: "AMAZON MKTPL*2K4TX81", cents: Int64(rng.int(1500...9000)),
                         alreadyCounted: false, category: .shopping),
                CardLine(day: Day(year: year, month: month, day: 27)!, memo: "PAYMENT THANK YOU", cents: 150_000,
                         alreadyCounted: true, category: .other, isPayment: true),
            ]
            if month == 7 {
                extra.append(CardLine(day: Day(year: year, month: month, day: 15)!, memo: "MARRIOTT BOSTON", cents: 48_812,
                                      alreadyCounted: false, category: .travel))
                extra.append(CardLine(day: Day(year: year, month: month, day: 21)!, memo: "AMAZON MKTPL REFUND", cents: 3310,
                                      alreadyCounted: false, category: .shopping, isRefund: true))
            }
            if month == 12 {
                extra.append(CardLine(day: Day(year: year, month: month, day: 6)!, memo: "CITY CAR WASH", cents: 1500,
                                      alreadyCounted: false, category: .other))
            }
            cardPurchases.append(contentsOf: extra)
        }

        // The first nine months on PDF statements; the last three from the
        // card's CSV export instead.
        for (index, (year, month)) in Self.months.enumerated() {
            let lines = cardPurchases.filter { $0.day.year == year && $0.day.month == month }.sorted { $0.day < $1.day }
            for line in lines where !line.alreadyCounted {
                ledger.append(Purchase(day: line.day, cents: line.cents, category: line.category, merchant: line.memo,
                                       isRefund: line.isRefund))
            }
            let last = DayRange.month(month, of: year)!.end
            if index < 9 {
                let header = ["CHASE", "Freedom Visa Statement", String(format: "Statement period %02d/01/%04d - %02d/%02d/%04d",
                                                                         month, year, month, last.day, year),
                              "New balance $1,204.33", "Minimum payment due $35.00"]
                let body = lines.map { line in
                    let amount = line.isRefund || line.isPayment ? "-" + Self.moneyWithCommas(line.cents) : Self.moneyWithCommas(line.cents)
                    return String(format: "%02d/%02d  ", line.day.month, line.day.day) + line.memo + "  " + amount
                }
                try ingest([Self.pdf(header), Self.pdf(body)], label: "statement \(year)-\(month)")
            } else {
                var csv = ["Transaction Date,Post Date,Description,Category,Type,Amount,Memo"]
                for line in lines {
                    let type = line.isPayment ? "Payment" : line.isRefund ? "Return" : "Sale"
                    let sign = line.isPayment || line.isRefund ? "" : "-"
                    csv.append(String(format: "%02d/%02d/%04d,%02d/%02d/%04d,", line.day.month, line.day.day, line.day.year,
                                      line.day.month, line.day.day, line.day.year)
                               + "\(line.memo),\(Self.bankCategory(line.category)),\(type),\(sign)\(Self.money(line.cents)),")
                }
                try ingest([RecognizedPage(lines: csv.map { RecognizedLine(text: $0) }, source: .file)], type: .csv,
                           label: "statement \(year)-\(month)")
            }
        }

        // A checking account export: rent, a paycheck, transfers, the
        // electric autopay (the bill is saved too, so it must count once).
        var checking = ["Date,Description,Amount,Balance"]
        for (year, month) in Self.months.suffix(3) {
            checking.append(String(format: "%04d-%02d-01,ZELLE PAYMENT TO OAK STREET PROPERTIES RENT,-2400.00,5100.00", year, month))
            checking.append(String(format: "%04d-%02d-15,ACME CORP PAYROLL DIRECT DEP,3150.00,8250.00", year, month))
            checking.append(String(format: "%04d-%02d-16,ONLINE TRANSFER TO SAVINGS,-500.00,7750.00", year, month))
            checking.append(String(format: "%04d-%02d-27,CHASE CREDIT CRD AUTOPAY,-1500.00,6250.00", year, month))
            ledger.append(Purchase(day: Day(year: year, month: month, day: 1)!, cents: 240_000, category: .other, merchant: "Rent"))
        }
        for (day, cents) in autopay {
            checking.append(String(format: "%04d-%02d-%02d,EVERSOURCE ENERGY AUTOPAY,-", day.year, day.month, day.day)
                            + Self.money(cents) + ",6000.00")
        }
        try ingest([RecognizedPage(lines: checking.map { RecognizedLine(text: $0) }, source: .file)], type: .csv,
                   label: "checking")
    }

    static func bankCategory(_ category: SpendCategory) -> String {
        switch category {
        case .groceries: "Groceries"
        case .dining: "Food & Drink"
        case .fuel: "Gas"
        case .shopping: "Shopping"
        case .subscriptions: "Entertainment"
        case .travel: "Travel"
        case .pharmacy: "Health & Wellness"
        case .utilities: "Bills & Utilities"
        case .other: "Personal"
        }
    }

    // MARK: Bills

    mutating func addBills() throws {
        for (index, (year, month)) in Self.months.enumerated() {
            let issued = Day(year: year, month: month, day: 3)!
            let due = issued.adding(days: 21)
            let kwh = 380 + (index * 37) % 220
            let cents = Int64(kwh) * 31 + 1150
            var text = ["Eversource", "Your Energy Bill", "Account number 5155-0101-22",
                        "Statement date " + Self.printedDate(issued, style: 0).prefix(10),
                        "Billing period " + String(format: "%02d/01/%04d", month == 1 ? 12 : month - 1, month == 1 ? year - 1 : year)
                            + " - " + String(format: "%02d/%02d/%04d", month, 1, year),
                        "Electricity used \(kwh) kWh", "Delivery charges  " + Self.money(cents * 45 / 100),
                        "Supply charges  " + Self.money(cents - cents * 45 / 100), "Amount due $" + Self.money(cents),
                        "Due date " + String(format: "%02d/%02d/%04d", due.month, due.day, due.year)]
            // Half the bills print the last balance too, as real ones do.
            if index % 2 == 1 { text.insert("Previous balance $" + Self.money(cents - 500) + " Payment received - thank you", at: 4) }
            let label = "electric \(year)-\(month)"
            let id = try ingest([Self.pdf(text)], label: label)
            expected.append(ExpectedRecord(id: id, kind: .bill, title: "Eversource Bill", totalCents: cents, category: .utilities,
                                           day: issued, label: label))
            ledger.append(Purchase(day: issued, cents: cents, category: .utilities, merchant: "Eversource"))
            if index >= 9 {
                autopay.append((due, cents))
            }
        }

        for (year, month) in Self.months.suffix(6) {
            let raised = (year, month) >= (2026, 8)
            let plan: Int64 = raised ? 9000 : 8000
            var lines = [("Unlimited Plus", plan), ("Device payment", 4167)]
            if raised { lines.append(("Disney Bundle", 1000)) }
            let taxes: Int64 = raised ? 2433 : 2033
            lines.append(("Taxes and fees", taxes))
            let total = lines.reduce(0) { $0 + $1.1 }
            let issued = Day(year: year, month: month, day: 5)!
            let text = ["verizon", "Account number 0442-1180-0001", "Bill date " + Self.printedDate(issued, style: 2)]
                + lines.map { $0.0 + "  " + Self.money($0.1) }
                + ["Total amount due $" + Self.money(total), "Pay by " + Self.printedDate(issued.adding(days: 20), style: 2)]
            let label = "phone \(year)-\(month)"
            let id = try ingest([Self.pdf(text)], label: label)
            expected.append(ExpectedRecord(id: id, kind: .bill, title: "Verizon Bill", totalCents: total, category: .utilities,
                                           day: issued, label: label))
            ledger.append(Purchase(day: issued, cents: total, category: .utilities, merchant: "Verizon"))
        }
    }

    var autopay: [(Day, Int64)] = []

    // MARK: IDs, policies, warranties, manuals

    mutating func addDocuments() throws {
        let documents: [(String, [String], RecordKind, Day?)] = [
            ("passport", ["UNITED STATES OF AMERICA", "PASSPORT", "Surname / Nom DOE", "Given names JORDAN ALEX",
                          "Date of issue 14 Mar 2021", "Date of expiration 13 Mar 2031", "Passport No. X00000000"],
             .identity, Day(year: 2031, month: 3, day: 13)),
            ("licence", ["STATE OF EXAMPLE", "DRIVER LICENSE", "DL D0000000", "DOB 01/02/1990", "ISS 07/22/2023", "EXP 07/22/2027",
                         "CLASS D"], .identity, Day(year: 2027, month: 7, day: 22)),
            ("registration", ["VEHICLE REGISTRATION", "2019 HONDA CIVIC", "Plate 0ABC000", "Registration expires 05/31/2027"],
             .identity, Day(year: 2027, month: 5, day: 31)),
            ("insurance", ["GEICO", "AUTO INSURANCE CARD", "Policy number 0000-00-000", "Effective 01/15/2026",
                           "Expiration 01/15/2027", "2019 HONDA CIVIC"], .identity, Day(year: 2027, month: 1, day: 15)),
            ("lease", ["RESIDENTIAL LEASE AGREEMENT", "Oak Street Properties", "Term: 09/01/2025 to 08/31/2026",
                       "Monthly rent $2,400.00"], .identity, Day(year: 2026, month: 8, day: 31)),
            ("tv warranty", ["SAMSUNG ELECTRONICS AMERICA", "LIMITED WARRANTY", "Model QN65Q80D", "Serial 0ABC1234XYZ",
                             "Date of purchase 03/14/2026", "Coverage ends 03/14/2027"], .warranty, Day(year: 2027, month: 3, day: 14)),
            ("tv manual", ["QN65Q80D User Manual", "Safety information", "Connecting devices", "Troubleshooting",
                           "Specifications"], .manual, nil),
            ("blender warranty", ["VITAMIX", "7-Year Full Warranty", "Model 5200", "Purchased 08/01/2026",
                                  "Warranty expires 08/01/2033"], .warranty, Day(year: 2033, month: 8, day: 1)),
            ("w2", ["Form W-2 Wage and Tax Statement 2025", "Employer ACME CORP", "Wages, tips 82000.00",
                    "Federal income tax withheld 9800.00"], .document, nil),
        ]
        for (label, lines, kind, day) in documents {
            let id = try ingest([Self.pdf(lines)], label: label)
            expected.append(ExpectedRecord(id: id, kind: kind, title: nil, totalCents: nil, category: nil, day: day, label: label))
        }
    }

    // MARK: Notes and screenshots

    mutating func addNotesAndScreenshots() throws {
        let notes = [
            ("hdmi note", "The spare HDMI cable is in the hall closet on the top shelf."),
            ("passport note", "Passports are in the fireproof box under the bed."),
            ("ladder note", "Lent the ladder to the neighbors at number 14."),
            ("paint note", "Living room paint is Benjamin Moore Pale Oak, eggshell finish."),
        ]
        for (label, text) in notes {
            let id = try ingest([RecognizedPage(lines: [RecognizedLine(text: text)], source: .speech)], type: .audio, label: label)
            expected.append(ExpectedRecord(id: id, kind: .item, title: nil, totalCents: nil, category: nil, day: nil, label: label))
        }

        let wifi = RecognizedPage(lines: [
            RecognizedLine(text: "9:41", box: PageRect(x: 0.08, y: 0.01, width: 0.1, height: 0.02)),
            RecognizedLine(text: "Photos", box: PageRect(x: 0.05, y: 0.07, width: 0.15, height: 0.025)),
            RecognizedLine(text: "Network name: Example-Guest", box: PageRect(x: 0.1, y: 0.40, width: 0.6, height: 0.02)),
            RecognizedLine(text: "Wi-Fi Password: purple-otter-77", box: PageRect(x: 0.1, y: 0.44, width: 0.6, height: 0.02)),
        ], source: .ocr)
        let wifiId = try ingest([wifi], type: .image, label: "wifi")
        expected.append(ExpectedRecord(id: wifiId, kind: nil, title: "Wi-Fi Network", totalCents: nil, category: nil, day: nil,
                                       label: "wifi"))

        let boarding = RecognizedPage(lines: [
            RecognizedLine(text: "10:05", box: PageRect(x: 0.08, y: 0.01, width: 0.1, height: 0.02)),
            RecognizedLine(text: "JetBlue", box: PageRect(x: 0.1, y: 0.10, width: 0.4, height: 0.05)),
            RecognizedLine(text: "Boarding Pass", box: PageRect(x: 0.1, y: 0.16, width: 0.4, height: 0.03)),
            RecognizedLine(text: "BOS to SFO  Flight 433", box: PageRect(x: 0.1, y: 0.22, width: 0.5, height: 0.02)),
            RecognizedLine(text: "Jul 14, 2026  Seat 12A", box: PageRect(x: 0.1, y: 0.26, width: 0.5, height: 0.02)),
        ], source: .ocr)
        let boardingId = try ingest([boarding], type: .image, label: "boarding pass")
        expected.append(ExpectedRecord(id: boardingId, kind: nil, title: "JetBlue", totalCents: nil, category: nil, day: nil,
                                       label: "boarding pass"))
    }

    // MARK: Expectations

    /// What the ledger says was spent, by category, in a range.
    func ledgerTotal(categories: Set<SpendCategory> = [], in range: DayRange? = nil) -> Int64 {
        ledger.filter { purchase in
            (categories.isEmpty || categories.contains(purchase.category)) && (range?.contains(purchase.day) ?? true)
        }
        .reduce(0) { $0 + ($1.isRefund ? -$1.cents : $1.cents) }
    }
}

/// SplitMix64: the same corpus every run.
struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            array.swapAt(i, int(0...i))
        }
    }
}

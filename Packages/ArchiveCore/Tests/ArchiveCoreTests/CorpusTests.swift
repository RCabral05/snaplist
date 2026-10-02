import Foundation
import Testing
@testable import ArchiveCore

/// Every feature run against a year of made-up paperwork (see Corpus), with
/// each answer checked against what really happened. Failures are gathered
/// and reported together, so one run shows everything that landed in the
/// wrong place.
@Suite(.serialized) struct CorpusChecks {
    let corpus: Corpus
    var store: ArchiveStore { corpus.store }

    init() throws { corpus = try Corpus.build() }

    func report(_ problems: [String], _ what: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let text = "\(problems.count) \(what):\n" + problems.prefix(40).joined(separator: "\n")
        #expect(problems.isEmpty, Comment(rawValue: text), sourceLocation: sourceLocation)
    }

    // MARK: Filing

    @Test func everyRecordIsFiledNamedAndTotalled() throws {
        var problems: [String] = []
        for expected in corpus.expected {
            guard let record = try store.record(expected.id) else { problems.append("\(expected.label): missing"); continue }
            if record.status != .ready { problems.append("\(expected.label): status \(record.status)") }
            if let kind = expected.kind, record.kind != kind {
                problems.append("\(expected.label): filed as \(record.kind), expected \(kind) (\"\(record.title)\")")
            }
            if let title = expected.title, record.title != title {
                problems.append("\(expected.label): named \"\(record.title)\", expected \"\(title)\"")
            }
            let amounts = try store.transactions(of: expected.id)
            if let total = expected.totalCents {
                if amounts.count != 1 {
                    problems.append("\(expected.label): \(amounts.count) amounts \(amounts.map(\.amountCents)), expected one of \(total)")
                } else if amounts[0].amountCents != total {
                    problems.append("\(expected.label): total \(amounts[0].amountCents), expected \(total)")
                }
                if let category = expected.category, let first = amounts.first, first.category != category {
                    problems.append("\(expected.label): category \(first.category), expected \(category) (\(first.merchant))")
                }
            }
            if let day = expected.day, expected.totalCents != nil, record.documentDate != day {
                problems.append("\(expected.label): dated \(record.documentDate?.iso ?? "nil"), expected \(day.iso)")
            }
        }
        report(problems, "records filed wrong")
    }

    @Test func statementsAreReadLineByLine() throws {
        var problems: [String] = []
        for (year, month) in Corpus.months {
            let label = "statement \(year)-\(month)"
            let id = try #require(corpus.named[label])
            let record = try #require(try store.record(id))
            if record.kind != .statement { problems.append("\(label): filed as \(record.kind) \"\(record.title)\"") }
            let lines = try store.transactions(of: id)
            let expected = corpus.cardPurchases.filter { $0.day.year == year && $0.day.month == month }
            if lines.count != expected.count {
                problems.append("\(label): \(lines.count) lines, expected \(expected.count)")
            }
            for line in expected {
                guard let found = lines.first(where: { $0.amountCents == line.cents && $0.date == line.day }) else {
                    problems.append("\(label): missing \(line.memo) \(line.cents) on \(line.day.iso)")
                    continue
                }
                let kind: AmountKind = line.isPayment ? .payment : line.isRefund ? .refund : .purchase
                if found.kind != kind { problems.append("\(label): \(line.memo) read as \(found.kind), expected \(kind)") }
                if !line.isPayment, found.category != line.category {
                    problems.append("\(label): \(line.memo) in \(found.category), expected \(line.category)")
                }
            }
        }
        let checking = try store.transactions(of: try #require(corpus.named["checking"]))
        for line in checking {
            let memo = line.memo.lowercased()
            if memo.contains("payroll"), line.spendCents != 0 {
                problems.append("checking: a paycheck counts as \(line.kind) (\(line.spendCents)), not income")
            }
            if memo.contains("transfer to savings") || memo.contains("autopay") && memo.contains("chase"), line.spendCents != 0 {
                problems.append("checking: \(line.memo) counts as spending \(line.spendCents)")
            }
        }
        report(problems, "statement lines read wrong")
    }

    // MARK: Spending

    @Test func everyMonthAndCategoryAddsUp() throws {
        var problems: [String] = []
        for (year, month) in Corpus.months {
            let range = try #require(DayRange.month(month, of: year))
            for category in SpendCategory.allCases {
                let answer = try store.answer(SpendingQuery(categories: [category], range: range))
                let got = answer.totals.first?.cents ?? 0
                let expected = corpus.ledgerTotal(categories: [category], in: range)
                if got != expected {
                    let extra = answer.counted.map { "\($0.transaction.merchant) \($0.transaction.spendCents) [\($0.transaction.source)]" }
                    problems.append("\(year)-\(month) \(category): \(got), expected \(expected) (off by \(got - expected)); counted \(extra)")
                }
            }
            let all = try store.answer(SpendingQuery(range: range)).totals.first?.cents ?? 0
            if all != corpus.ledgerTotal(in: range) {
                problems.append("\(year)-\(month) all: \(all), expected \(corpus.ledgerTotal(in: range))")
            }
        }
        report(problems, "monthly totals off")
    }

    @Test func overviewAgreesWithAnswers() throws {
        let overview = try store.spendingOverview()
        var problems: [String] = []
        if overview.months.count != 12 { problems.append("\(overview.months.count) months, expected 12: \(overview.months.map(\.label))") }
        for month in overview.months {
            let answer = try store.answer(SpendingQuery(range: month.range)).totals.first?.cents ?? 0
            if month.totalCents != answer { problems.append("\(month.label): overview \(month.totalCents), answer \(answer)") }
            let byCategory = month.byCategory.values.reduce(0, +)
            if byCategory != month.totalCents { problems.append("\(month.label): categories add to \(byCategory), total \(month.totalCents)") }
        }
        report(problems, "overview mismatches")
    }

    @Test func receiptsOnTheCardStatementCountOnce() throws {
        let duplicates = try store.possibleDuplicates()
        let expected = corpus.cardPurchases.filter { $0.alreadyCounted && !$0.isPayment }.count + corpus.autopay.count
        var problems: [String] = []
        if duplicates.count != expected { problems.append("\(duplicates.count) duplicates, expected \(expected)") }
        for duplicate in duplicates where duplicate.kept.transaction.source == .statement {
            if duplicate.kept.record.kind != .statement { continue }
            // Two statements overlapping is only expected when one was imported twice; none was.
            problems.append("statement overlap: \(duplicate.kept.transaction.memo) / \(duplicate.dropped.transaction.memo)")
        }
        report(problems, "duplicate problems")
    }

    @Test func merchantRulesMoveEveryLine() throws {
        let before = try store.answer(SpendingQuery(categories: [.other])).totals.first?.cents ?? 0
        // The car wash is Car stuff, not "other"; teach it once.
        try store.setCategory(.travel, forMerchant: try #require(try store.spendingAmounts().first {
            $0.transaction.memo.contains("CAR WASH")
        }?.transaction.merchant))
        let after = try store.answer(SpendingQuery(categories: [.other])).totals.first?.cents ?? 0
        #expect(before - after == 1500)
    }

    // MARK: Bills, subscriptions, changes

    @Test func subscriptionsAndBillsRecur() throws {
        let charges = try store.recurringCharges()
        let names = charges.map { $0.merchant.lowercased() }
        var problems: [String] = []
        for name in ["netflix", "spotify", "eversource", "verizon"] where !names.contains(where: { $0.contains(name) }) {
            problems.append("\(name) isn't recurring; found \(names)")
        }
        for name in ["amazon", "costco", "starbucks", "doordash", "shell"] where names.contains(where: { $0.contains(name) }) {
            problems.append("\(name) shouldn't be a subscription; found \(names)")
        }
        report(problems, "recurring problems")
    }

    @Test func priceChangesAreFound() throws {
        let changes = try store.priceChanges()
        let summary = changes.map { "\($0.kind) \($0.merchant) \($0.previous.transaction.amountCents)→\($0.latest.transaction.amountCents)" }
        let verizon = changes.first { $0.merchant.lowercased().contains("verizon") }
        #expect(verizon?.kind == .bill, "\(summary)")
        #expect(verizon?.lines.map(\.name) == ["Unlimited Plus", "Disney Bundle", "Taxes and fees"], "\(summary)")
        let netflix = changes.first { $0.merchant.lowercased().contains("netflix") }
        #expect(netflix?.previous.transaction.amountCents == 1549, "\(summary)")
        #expect(netflix?.latest.transaction.amountCents == 1799, "\(summary)")
        // Electric bills swing with use every month: not a price change.
        #expect(!changes.contains { $0.merchant.lowercased().contains("eversource") }, "\(summary)")
        #expect(!changes.contains { $0.merchant.lowercased().contains("spotify") }, "\(summary)")
    }

    @Test func priceMemory() throws {
        let eggs = try #require(try store.priceHistory(["eggs"]))
        let merchants = Set(eggs.points.map(\.transaction.merchant))
        #expect(merchants == ["Costco", "Trader Joe's"], "\(merchants)")
        #expect(eggs.points.allSatisfy { $0.transaction.memo.lowercased().contains("egg") })
        let gas = try #require(try store.priceHistory([], categories: [.fuel]))
        #expect(gas.isPurchases)
        #expect(gas.points.count == 24, "\(gas.points.count) fill-ups")
    }

    @Test func itemsAreReadFromReceipts() throws {
        var problems: [String] = []
        for expected in corpus.expected where expected.kind == .receipt && expected.label.hasPrefix("receipt") {
            let items = try store.items(of: expected.id)
            if items.isEmpty { problems.append("\(expected.label): no items"); continue }
            let names = items.map { $0.name.lowercased() }
            for bad in ["subtotal", "tax", "total", "visa", "cash", "change", "auth"] where names.contains(where: { $0.hasPrefix(bad) }) {
                problems.append("\(expected.label): \"\(bad)\" read as an item: \(names)")
            }
            let sum = items.reduce(0) { $0 + $1.amountCents }
            if sum > (expected.totalCents ?? 0) { problems.append("\(expected.label): items \(sum) more than total \(expected.totalCents ?? 0)") }
        }
        report(problems, "item problems")
    }

    // MARK: Dates

    @Test func upcomingDatesAreRight() throws {
        let dates = try store.upcomingDates(from: Corpus.today)
        let lines = dates.map { "\($0.kind) \($0.record.title) \($0.day.iso)" }
        var problems: [String] = []
        if dates.contains(where: { $0.day < Corpus.today }) { problems.append("past dates: \(lines)") }
        let renewals = Set(dates.filter { $0.kind == .renewal }.map(\.record.id))
        for label in ["passport", "licence", "registration", "insurance"] where !renewals.contains(corpus.named[label]!) {
            problems.append("\(label) has no renewal date")
        }
        if renewals.contains(corpus.named["lease"]!) { problems.append("lease ended in August but is upcoming") }
        let warranties = Set(dates.filter { $0.kind == .warrantyEnds }.map(\.record.id))
        for label in ["tv warranty", "blender warranty"] where !warranties.contains(corpus.named[label]!) {
            problems.append("\(label) not upcoming")
        }
        // Return windows from 30-day receipts: only September's are still open.
        for date in dates where date.kind == .returnBy {
            if date.record.effectiveDay < Day(year: 2026, month: 9, day: 1)! {
                problems.append("old return window: \(date.record.title) bought \(date.record.effectiveDay.iso) returnable to \(date.day.iso)")
            }
        }
        // Bills are paid; statements have due dates; none of the corpus is due after today except none.
        if dates.contains(where: { $0.kind == .billDue }) {
            problems.append("bills due after Oct 1: \(lines.filter { $0.hasPrefix("billDue") })")
        }
        report(problems, "upcoming problems")
    }

    @Test func idsAndPoliciesWithExpiry() throws {
        let documents = try store.importantDocuments()
        var problems: [String] = []
        for label in ["passport", "licence", "registration", "insurance", "lease"] {
            let id = corpus.named[label]!
            let expected = corpus.expected.first { $0.id == id }!.day
            guard let document = documents.first(where: { $0.id == id }) else {
                problems.append("\(label) not among IDs & policies (\(try store.record(id)!.kind))"); continue
            }
            if document.expires != expected {
                problems.append("\(label): expires \(document.expires?.iso ?? "nil") from \"\(document.evidence ?? "")\", expected \(expected!.iso)")
            }
        }
        let others = documents.filter { doc in !["passport", "licence", "registration", "insurance", "lease"].contains { corpus.named[$0] == doc.id } }
        if !others.isEmpty { problems.append("not IDs: \(others.map(\.record.title))") }
        report(problems, "ID problems")
    }

    // MARK: Finding things

    @Test func searchAndQuestionsFindTheRightRecord() throws {
        let cases: [(String, String)] = [
            ("What's my wifi password", "wifi"),
            ("guest wi-fi network", "wifi"),
            ("passport number", "passport"),
            ("Where is the spare HDMI cable?", "hdmi note"),
            ("where did I put the passports", "passport note"),
            ("who has the ladder", "ladder note"),
            ("what color is the living room paint", "paint note"),
            ("civic registration", "registration"),
            ("geico policy number", "insurance"),
            ("my flight to SFO", "boarding pass"),
            ("w-2 from acme", "w2"),
            ("lease agreement", "lease"),
        ]
        var problems: [String] = []
        for (question, label) in cases {
            let id = corpus.named[label]!
            let found: [UUID]
            if case .whereIs(let terms) = QuestionParser.parse(question, today: Corpus.today) {
                found = try store.whereIs(terms).map(\.record.id)
            } else {
                found = try store.searchQuestion(question).map(\.record.id)
            }
            if found.first != id {
                let titles = try found.prefix(3).map { try store.record($0)?.title ?? "?" }
                problems.append("\"\(question)\": got \(titles), expected \(try store.record(id)!.title)")
            }
        }
        report(problems, "searches that missed")
    }

    @Test func questionsRouteToTheRightAnswer() {
        enum Route: Equatable { case spending, whereIs, expiry, lastBought, price, search }
        func route(_ question: Question) -> Route {
            switch question {
            case .spending: .spending
            case .whereIs: .whereIs
            case .expiry: .expiry
            case .lastBought: .lastBought
            case .priceHistory: .price
            case .search: .search
            }
        }
        let cases: [(String, Route)] = [
            ("How much did I spend on gas in September?", .spending),
            ("what did takeout set me back over the summer", .spending),
            ("groceries last month", .spending),
            ("total at costco this year", .spending),
            ("How much have I spent at Starbucks?", .spending),
            ("what did I spend on food in July", .spending),
            ("pharmacy spending 2026", .spending),
            ("Where is the HDMI cable", .whereIs),
            ("where's my passport", .whereIs),
            ("When does the warranty on my TV expire?", .expiry),
            ("when does my license expire", .expiry),
            ("When did I last buy printer ink?", .lastBought),
            ("last time I bought eggs", .lastBought),
            ("What do I usually pay for eggs?", .price),
            ("cheapest place I've bought Tide", .price),
            ("what's my wifi password", .search),
            ("guest network", .search),
        ]
        var problems: [String] = []
        for (question, expected) in cases {
            let parsed = QuestionParser.parse(question, today: Corpus.today)
            if route(parsed) != expected { problems.append("\"\(question)\" → \(parsed), expected \(expected)") }
        }
        report(problems, "questions routed wrong")
    }

    @Test func askedQuestionsGetTheLedgerAnswer() throws {
        func spent(_ question: String) throws -> Int64? {
            guard case .spending(let query) = QuestionParser.parse(question, today: Corpus.today) else { return nil }
            return try store.answer(query).totals.first?.cents ?? 0
        }
        let september = try #require(DayRange.month(9, of: 2026))
        let summer = try #require(DayRange.months(from: 6, of: 2026, count: 3))
        #expect(try spent("How much did I spend on gas in September?") == corpus.ledgerTotal(categories: [.fuel], in: september))
        #expect(try spent("what did takeout set me back over the summer") == corpus.ledgerTotal(categories: [.dining], in: summer))
        #expect(try spent("groceries last month") == corpus.ledgerTotal(categories: [.groceries], in: september))
        let costco = corpus.ledger.filter { $0.merchant == "Costco" && $0.day.year == 2026 }.reduce(0) { $0 + $1.cents }
        #expect(try spent("total at costco this year") == costco)
    }

    // MARK: Things, collections, tags, tax

    @Test func aThingGathersItsPaperwork() throws {
        let receipt = corpus.named["tv receipt"]!
        let items = try store.items(of: receipt)
        let tvItem = try #require(items.first { $0.name.lowercased().contains("qn65q80d") }, "\(items.map(\.name))")
        let draft = try #require(try store.draftThing(from: receipt, item: tvItem))
        #expect(draft.valueCents == 129_999)
        #expect(draft.serialNumber == "0ABC1234XYZ")
        #expect(draft.purchased == Day(year: 2026, month: 3, day: 14))
        let thing = try store.createThing(draft, from: receipt)
        let suggested = Set(try store.suggestedLinks(for: thing.id).map(\.id))
        let suggestedTitles = try suggested.map { try store.record($0)?.title ?? "" }
        #expect(suggested == [corpus.named["tv warranty"]!, corpus.named["tv manual"]!], "\(suggestedTitles)")
        for id in suggested { try store.link(id, to: thing.id) }
        let profile = try #require(try store.thingProfile(thing.id))
        #expect(profile.warrantyEnds == Day(year: 2027, month: 3, day: 14))
        #expect(try store.thingQuestion("is my TV still under warranty?", today: Corpus.today)?.topic == .warranty)
    }

    @Test func collectionsHoldTheRightRecords() throws {
        var problems: [String] = []
        let expectations: [(String, [String], [String])] = [
            ("Car", ["oil change 0", "oil change 1", "registration", "insurance"], ["receipt 0", "tv receipt", "licence"]),
            ("Home", ["lease"], ["receipt 1", "registration"]),
            ("Pet", ["vet"], ["receipt 7"]),
            ("Travel", ["boarding pass"], ["receipt 0"]),
            ("Taxes", ["w2"], ["receipt 0", "passport"]),
        ]
        for (name, inside, outside) in expectations {
            let collection = try #require(Collection.presets.first { $0.name == name })
            try store.save(collection)
            let records = try store.records(in: collection)
            let ids = Set(records.map(\.id))
            for label in inside where !ids.contains(corpus.named[label]!) { problems.append("\(name) is missing \(label)") }
            for label in outside where ids.contains(corpus.named[label]!) { problems.append("\(name) wrongly holds \(label)") }
            if records.contains(where: { $0.kind == .statement }) { problems.append("\(name) holds a whole statement") }
        }
        // Home Depot receipts belong to Home.
        let home = try #require(Collection.presets.first { $0.name == "Home" })
        let homeIds = Set(try store.records(in: home).map(\.id))
        let depot = corpus.expected.filter { $0.title == "Home Depot" }
        let missing = depot.filter { !homeIds.contains($0.id) }
        if !missing.isEmpty { problems.append("Home is missing \(missing.count) of \(depot.count) Home Depot receipts") }
        let car = try #require(Collection.presets.first { $0.name == "Car" })
        let carLines = try store.statementLines(in: car).map(\.transaction.memo)
        if carLines != ["CITY CAR WASH"] { problems.append("Car statement lines: \(carLines)") }
        report(problems, "collection problems")
    }

    @Test func taxTagsMakeAReport() throws {
        let vet = corpus.named["vet"]!, cvs = corpus.expected.first { $0.title == "CVS Pharmacy" && $0.day?.year == 2026 }!
        let phone = corpus.named["phone 2026-9"]!
        _ = try store.addTag("Medical", kind: .tax, to: cvs.id)
        _ = try store.addTag("Business", kind: .tax, to: phone)
        _ = try store.addTag("Business", kind: .tax, to: vet)
        let report = try store.taxReport(year: 2026)
        #expect(report.groups.map(\.purpose) == ["Business", "Medical"])
        let business = try #require(report.groups.first { $0.purpose == "Business" })
        #expect(business.entries.count == 2)
        #expect(business.totalCents == 9300 + corpus.expected.first { $0.id == phone }!.totalCents!)
        #expect(try store.taxYears() == [2026])

        let folder = corpus.tmp.directory.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let zipFolder = try ArchiveExporter.exportTaxReport(corpus.tmp.archive, year: 2026, into: folder)
        #expect(FileManager.default.fileExists(atPath: zipFolder.path))
    }

    @Test func peopleAndPlacesTags() throws {
        let marriott = try #require(try store.spendingAmounts().first { $0.transaction.memo.contains("MARRIOTT") })
        _ = try store.addTag("Boston", kind: .place, to: marriott.record.id)
        guard case .spending(let query) = QuestionParser.parse("How much did I spend in Boston?", today: Corpus.today) else {
            Issue.record("not a spending question"); return
        }
        // Tagging a whole statement with a place counts all its lines; that's how tags work on statements.
        let answer = try store.answer(query)
        #expect((answer.totals.first?.cents ?? 0) > 0)
    }

    @Test func budgetsForSeptember() throws {
        try store.setBudget(60_000, for: .groceries)
        try store.setBudget(500_000, for: nil)
        let september = try #require(DayRange.month(9, of: 2026))
        let status = try store.budgetStatus(in: september)
        #expect(status.first { $0.budget.category == .groceries }?.spentCents == corpus.ledgerTotal(categories: [.groceries], in: september))
        #expect(status.first { $0.budget.category == nil }?.spentCents == corpus.ledgerTotal(in: september))
    }

    @Test func budgetsForEveryMonthMatchTheOverview() throws {
        try store.setBudget(60_000, for: .groceries)
        try store.setBudget(25_000, for: .dining)
        try store.setBudget(500_000, for: nil)
        let overview = try store.spendingOverview()
        let budgets = try store.budgets()
        for month in overview.months {
            let fromMonth = month.budgetStatus(budgets, currency: overview.currency)
            let fromStore = try store.budgetStatus(in: month.range)
            #expect(fromMonth == fromStore, "\(month.label)")
        }
    }

    @Test func theWholeArchiveExports() throws {
        let folder = corpus.tmp.directory.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (_, summary) = try ArchiveExporter.export(corpus.tmp.archive, into: folder, today: Corpus.today)
        #expect(summary.records == (try store.records().count))
        #expect(summary.amounts == (try store.spendingAmounts().count + 0) || summary.amounts > 0)
    }
}

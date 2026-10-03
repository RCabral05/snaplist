import Foundation

/// A question, understood well enough to answer from stored records with
/// ordinary code. Parsing is rules, not a language model, so it works on
/// every iPhone and the same words always mean the same thing.
public enum Question: Equatable, Sendable {
    /// "How much did I spend on gas in September?"
    case spending(SpendingQuery)
    /// "Where did I put the spare HDMI cable?"
    case whereIs(terms: [String])
    /// "When does the warranty on my TV expire?"
    case expiry(terms: [String])
    /// "When did I last buy printer ink?"
    case lastBought(terms: [String])
    /// "What do I usually pay for eggs?", "Cheapest place I've bought Tide?"
    case priceHistory(terms: [String], categories: Set<SpendCategory>)
    /// Anything else: a plain search.
    case search(String)
}

public struct SpendingQuery: Hashable, Sendable {
    public var categories: Set<SpendCategory> = []
    /// Words that must appear in the merchant, the printed line or the
    /// record's name: "costco", "amazon".
    public var merchantTerms: [String] = []
    public var range: DayRange?
    /// How the range reads back: "September 2026", "this year".
    public var rangeLabel: String?
    /// Caveats about how the words were read, shown with the answer.
    public var notes: [String] = []
    /// Only amounts on these records count: a collection like Car.
    public var onlyRecords: Set<UUID>?
    /// Statement lines count too when they mention one of these (a
    /// collection's words): "JIFFY LUBE" for Car.
    public var lineKeywords: [String] = []
    /// The collection's name, for the answer's wording.
    public var scopeLabel: String?
    /// Receipts and bills whose printed text has one of `merchantTerms`
    /// though their store's name doesn't: "dispensary" on a receipt from
    /// "Green Leaf Wellness". Filled in while answering.
    var textMatchedRecords: Set<UUID> = []
    /// "What did I get at the dispensary?": the things bought, not only the total.
    public var listsItems = false

    public init(categories: Set<SpendCategory> = [], merchantTerms: [String] = [], range: DayRange? = nil,
                rangeLabel: String? = nil, notes: [String] = []) {
        self.categories = categories
        self.merchantTerms = merchantTerms
        self.range = range
        self.rangeLabel = rangeLabel
        self.notes = notes
    }
}

public enum QuestionParser {
    public static func parse(_ question: String, today: Day) -> Question {
        var text = " " + question.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet(charactersIn: "?!.,;:\"")).joined(separator: " ") + " "

        if text.contains(" where ") || text.contains(" where's ") {
            return .whereIs(terms: terms(in: text, dropping: whereWords))
        }
        // "Last time I bought eggs" is when; "what I paid last time" is how much.
        let bought = [" buy ", " bought ", " purchase ", " purchased ", " get ", " got "]
        let money = [" pay ", " paid ", " cost ", " costs ", " price ", " spend ", " spent ", " much "]
        if text.contains(" last time "), bought.contains(where: { text.contains($0) }), !money.contains(where: { text.contains($0) }) {
            return .lastBought(terms: terms(in: text, dropping: lastBoughtWords))
        }
        if priceWords.contains(where: { text.contains($0) }) {
            var categories: Set<SpendCategory> = []
            var rest = text
            for (words, found, _) in categoryWords {
                if let word = words.first(where: { rest.contains(" \($0) ") }) {
                    categories.formUnion(found)
                    rest = rest.replacingOccurrences(of: " \(word) ", with: " ")
                }
            }
            let terms = terms(in: text, dropping: priceFiller)
            if !terms.isEmpty || !categories.isEmpty {
                return .priceHistory(terms: terms, categories: categories)
            }
        }
        if text.contains(" when "), bought.contains(where: { text.contains($0) }) {
            return .lastBought(terms: terms(in: text, dropping: lastBoughtWords))
        }
        if text.contains("expire") || text.contains("expiration") || (text.contains("warranty") && text.contains(" when ")) {
            return .expiry(terms: terms(in: text, dropping: expiryWords))
        }
        let dated = dateRange(in: text, today: today)
        // "food this fall" is about money too: a category and a period.
        let namesCategory = categoryWords.contains { words, _, _ in words.contains { text.contains(" \($0) ") } }
        guard spendingWords.contains(where: { text.contains($0) }) || (namesCategory && dated != nil) else {
            return .search(question.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var query = SpendingQuery()
        if let (range, label, matched) = dated {
            query.range = range
            query.rangeLabel = label
            text = text.replacingOccurrences(of: matched, with: " ")
        }
        for (words, categories, note) in categoryWords {
            guard let word = words.first(where: { text.contains(" \($0) ") }) else { continue }
            query.categories.formUnion(categories)
            if let note { query.notes.append(note) }
            text = text.replacingOccurrences(of: " \(word) ", with: " ")
        }
        query.merchantTerms = terms(in: text, dropping: spendingFiller)
        query.listsItems = asksWhatWasBought(question)
        return .spending(query)
    }

    /// Whether a question is about money at all. A model reading "what psi
    /// should my tires be" as shopping at "Tire" is overruled when it isn't.
    public static func mentionsMoney(_ question: String) -> Bool {
        let text = " " + question.lowercased().replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet(charactersIn: "?!.,;:\"")).joined(separator: " ") + " "
        if text.contains("$") { return true }
        let words = [" spend ", " spent ", " spending ", " cost ", " costs ", " pay ", " paid ", " paying ", " price ",
                     " prices ", " how much ", " total ", " budget ", " bill ", " bills ", " charge ", " charged ",
                     " buy ", " bought ", " purchase ", " purchased ", " order ", " ordered ", " expensive ", " cheap ",
                     " money ", " dollars ", " set me back ", " receipt ", " receipts ", " get at ", " got at "]
        return words.contains { text.contains($0) }
    }

    /// "What did I get at…", "what have I bought from…": asking for the things.
    public static func asksWhatWasBought(_ question: String) -> Bool {
        let text = " " + question.lowercased().replacingOccurrences(of: "’", with: "'") + " "
        return [" what did i get ", " what did i buy ", " what did i purchase ", " what did i order ", " what have i bought ",
                " what have i gotten ", " what i got ", " what i bought ", " what did we get ", " what did we buy "]
            .contains { text.contains($0) }
    }

    // MARK: Words

    static let spendingWords = ["how much", "spend", "spent", "total", "cost", "bill", " pay", "paid",
                                "what was my", "what did i", "set me back", "set us back", " blew ", " blow ",
                                "shell out", "shelled out", "fork out", "forked out", " drop on ", " dropped on "]

    /// Phrase → categories, with a note when the phrase is ambiguous.
    static let categoryWords: [([String], Set<SpendCategory>, String?)] = [
        (["gas station", "gasoline", "fuel", "gas"], [.fuel],
         "\"Gas\" was read as fuel. Gas utility bills aren't included; ask about utilities for those."),
        (["electric bill", "electricity", "electric", "power bill", "utilities", "utility", "water bill",
          "internet", "phone bill", "cable bill"], [.utilities], nil),
        (["groceries", "grocery", "supermarket"], [.groceries], nil),
        (["eating out", "restaurants", "restaurant", "dining", "takeout", "take out", "coffee", "lunch", "dinner"],
         [.dining], nil),
        (["food"], [.groceries, .dining], "\"Food\" counts groceries and eating out."),
        (["pharmacy", "prescriptions", "medicine"], [.pharmacy], nil),
        (["subscriptions", "subscription", "streaming"], [.subscriptions], nil),
        (["shopping"], [.shopping], nil),
        (["travel", "rides", "flights", "hotels"], [.travel], nil),
    ]

    static let filler: Set<String> = [
        "how", "much", "did", "do", "does", "i", "my", "me", "we", "our", "the", "a", "an", "on", "at", "in",
        "for", "of", "to", "from", "with", "was", "were", "is", "are", "it", "this", "that", "what", "whats",
        "what's", "when", "and", "or", "have", "has", "had", "all", "any", "there", "be", "been", "get", "got",
        "put", "keep", "kept", "stuff", "things", "thing", "so", "far", "may", "might", "can", "could",
        "would", "should", "will", "ever", "up", "out", "about", "around", "roughly", "approximately",
        "us", "over", "during", "since", "past", "last", "entire", "whole", "just", "only", "lately",
        "recently", "altogether", "overall",
    ]
    static let spendingFiller = filler.union(["spend", "spent", "spending", "total", "cost", "costs", "bill",
                                              "blow", "blew", "drop", "dropped", "shelled", "fork", "forked",
                                              "set", "back", "run", "ran", "go", "went", "like",
                                              "bills", "pay", "paid", "money", "charges", "charged", "purchases",
                                              "bought", "buy", "dollars", "amount"])
    static let whereFiller = filler.union(["where", "where's", "wheres", "left", "store", "stored", "find", "can"])
    static let whereWords = whereFiller
    /// Questions about a price rather than a total.
    static let priceWords = [" last time ", " usually ", " normally ", " typically ", " on average ", " average ",
                             " cheapest ", " cheaper ", " gone up ", " went up ", " go up ", " increased ", " increase ",
                             " price of ", " price for ", " prices ", " price history ", " cost per "]
    static let priceFiller = filler.union(["last", "time", "usually", "normally", "typically", "average", "cheapest",
                                           "cheaper", "gone", "went", "go", "increased", "increase", "price", "prices",
                                           "history", "pay", "paid", "cost", "costs", "per", "place", "where", "store",
                                           "bought", "buy", "spend", "spent", "much", "for", "the", "what", "whats",
                                           "what's", "has", "have", "i've", "ive", "my", "is", "do", "did"])
    static let lastBoughtWords = filler.union(["when", "last", "buy", "bought", "purchase", "purchased", "get", "got",
                                               "time", "recently", "some", "new", "more"])
    static let expiryWords = filler.union(["expire", "expires", "expiring", "expiration", "date", "end", "ends",
                                           "run", "out", "warranty", "warranties", "coverage", "covered", "until",
                                           "valid", "still"])

    static func terms(in text: String, dropping words: Set<String>) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
            .filter { !words.contains($0) && $0.count(where: { $0.isLetter || $0.isNumber }) >= 2 }
    }

    // MARK: Dates

    /// The first date range mentioned, how to describe it, and the words it
    /// took up.
    static func dateRange(in text: String, today: Day) -> (DayRange, String, String)? {
        let relative: [(String, () -> (DayRange, String)?)] = [
            ("last month", {
                let month = today.month == 1 ? 12 : today.month - 1
                let year = today.month == 1 ? today.year - 1 : today.year
                return DayRange.month(month, of: year).map { ($0, monthLabel(month, year)) }
            }),
            ("this month", { DayRange.month(today.month, of: today.year).map { ($0, "this month") } }),
            ("last year", { DayRange.year(today.year - 1).map { ($0, String(today.year - 1)) } }),
            ("this year", { DayRange.year(today.year).map { ($0, "this year") } }),
            ("last week", { (DayRange(today.adding(days: -7), today), "the last 7 days") }),
            ("this week", { (DayRange(today.adding(days: -6), today), "the last 7 days") }),
            ("yesterday", { (DayRange(today.adding(days: -1), today.adding(days: -1)), "yesterday") }),
            ("today", { (DayRange(today, today), "today") }),
        ]
        for (phrase, build) in relative where text.contains(" \(phrase) ") {
            if let (range, label) = build() { return (range, label, " \(phrase) ") }
        }

        // "september", "sept 2025", "in august"
        let monthRegex = DayParser.regex("\\s(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?(?:\\s+(\\d{4}))?\\s")
        let ns = text as NSString
        for match in monthRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let word = ns.substring(with: match.range(at: 1))
            // "may" is also a verb; only count it with a year or after "in".
            let full = ns.substring(with: match.range).trimmingCharacters(in: .whitespaces)
            if word == "may", match.range(at: 2).location == NSNotFound, !text.contains(" in may ") { continue }
            guard let month = DayParser.month(named: word),
                  DayParser.months.contains(where: { full.hasPrefix($0) }) else { continue }
            let year: Int
            if match.range(at: 2).location != NSNotFound {
                year = Int(ns.substring(with: match.range(at: 2))) ?? today.year
            } else {
                // The most recent one: in October, "September" is this year's.
                year = month <= today.month ? today.year : today.year - 1
            }
            guard let range = DayRange.month(month, of: year) else { continue }
            return (range, monthLabel(month, year), ns.substring(with: match.range) + " ")
        }

        // "over the summer", "last winter", "spring 2025": northern seasons by
        // month, the most recent one that has started.
        let seasonRegex = DayParser.regex("\\s(?:(last|this)\\s+)?(spring|summer|fall|autumn|winter)(?:\\s+((?:19|20)\\d{2}))?\\s")
        if let match = seasonRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            let season = ns.substring(with: match.range(at: 2))
            let first = ["spring": 3, "summer": 6, "fall": 9, "autumn": 9, "winter": 12][season] ?? 6
            var year: Int
            if match.range(at: 3).location != NSNotFound, let named = Int(ns.substring(with: match.range(at: 3))) {
                // "winter 2026" is the one that ends in 2026.
                year = first == 12 ? named - 1 : named
            } else {
                let startedThisYear = first <= today.month
                year = startedThisYear ? today.year : today.year - 1
                if match.range(at: 1).location != NSNotFound, ns.substring(with: match.range(at: 1)) == "last",
                   let current = DayRange.months(from: first, of: year, count: 3), current.contains(today) {
                    year -= 1
                }
            }
            if let range = DayRange.months(from: first, of: year, count: 3) {
                let name = season == "autumn" ? "fall" : season
                let label = first == 12 ? "winter \(year)–\(year + 1)" : "\(name) \(year)"
                return (range, label, ns.substring(with: match.range))
            }
        }

        // "in 2025"
        let yearRegex = DayParser.regex("\\s((?:19|20)\\d{2})\\s")
        if let match = yearRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
           let year = Int(ns.substring(with: match.range(at: 1))), let range = DayRange.year(year) {
            return (range, String(year), ns.substring(with: match.range))
        }
        return nil
    }

    static func monthLabel(_ month: Int, _ year: Int) -> String {
        let names = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                     "October", "November", "December"]
        return "\(names[month - 1]) \(year)"
    }
}

/// A question as a language model read it, in fixed fields: what kind of
/// question, which categories, merchants and period. The model fills these
/// in and nothing else; `QuestionParser.question(from:today:)` turns them
/// into a `Question` with the same rules as typed words, and the answer is
/// still worked out by ordinary code.
public struct Interpretation: Equatable, Sendable {
    public enum Intent: Equatable, Sendable { case spending, whereIs, expiry, search }

    public enum Period: Equatable, Sendable {
        case anyTime, thisMonth, lastMonth, thisYear, lastYear
        /// Month 1–12, in `year` if given, else the most recent one.
        case month(Int, year: Int?)
        case year(Int)
    }

    public var intent: Intent
    public var categories: Set<SpendCategory>
    public var merchants: [String]
    /// The thing asked about, for where and expiry questions.
    public var subject: [String]
    public var period: Period

    public init(intent: Intent, categories: Set<SpendCategory> = [], merchants: [String] = [],
                subject: [String] = [], period: Period = .anyTime) {
        self.intent = intent
        self.categories = categories
        self.merchants = merchants
        self.subject = subject
        self.period = period
    }
}

extension QuestionParser {
    public static func question(from interpretation: Interpretation, original: String, today: Day) -> Question {
        let words = { (phrases: [String]) in
            phrases.flatMap { $0.lowercased().split(whereSeparator: \.isWhitespace).map(String.init) }
                .filter { !filler.contains($0) && $0.count >= 2 }
        }
        switch interpretation.intent {
        case .search:
            return .search(original.trimmingCharacters(in: .whitespacesAndNewlines))
        case .whereIs:
            let terms = words(interpretation.subject)
            return terms.isEmpty ? .search(original) : .whereIs(terms: terms)
        case .expiry:
            return .expiry(terms: words(interpretation.subject))
        case .spending:
            var query = SpendingQuery(categories: interpretation.categories.subtracting([.other]),
                                      merchantTerms: interpretation.merchants
                                          .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                                          .filter { $0.count >= 2 })
            if let (range, label) = range(of: interpretation.period, today: today) {
                query.range = range
                query.rangeLabel = label
            }
            query.listsItems = QuestionParser.asksWhatWasBought(original)
            return .spending(query)
        }
    }

    static func range(of period: Interpretation.Period, today: Day) -> (DayRange, String)? {
        let phrase: String
        switch period {
        case .anyTime: return nil
        case .thisMonth: phrase = "this month"
        case .lastMonth: phrase = "last month"
        case .thisYear: phrase = "this year"
        case .lastYear: phrase = "last year"
        case .month(let month, let year):
            guard (1...12).contains(month) else { return nil }
            let resolved = year ?? (month <= today.month ? today.year : today.year - 1)
            return DayRange.month(month, of: resolved).map { ($0, monthLabel(month, resolved)) }
        case .year(let year):
            return DayRange.year(year).map { ($0, String(year)) }
        }
        return dateRange(in: " \(phrase) ", today: today).map { ($0.0, $0.1) }
    }
}

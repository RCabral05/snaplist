import Foundation

/// A name and category guessed from a record's text.
public struct Suggestion: Equatable, Sendable {
    public var title: String?
    public var kind: RecordKind?
}

/// Guesses what a document is and what to call it, from the text alone, on
/// the phone, with plain rules. Wrong guesses are cheap: nothing a person has
/// named or filed is touched, and anything can be edited.
///
/// The name is a known merchant or issuer near the top if there is one (the
/// earliest wins, so a CVS receipt that mentions Panera further down is still
/// CVS), otherwise the most prominent line near the top: the tallest one when
/// OCR gave positions, which on a receipt is usually the store's name.
enum Suggester {
    static func suggest(_ pages: [RecognizedPage]) -> Suggestion {
        guard !pages.isEmpty else { return Suggestion() }
        if pages.allSatisfy({ $0.source == .speech }) {
            return Suggestion(title: noteTitle(pages.map(\.text).joined(separator: " ")), kind: .item)
        }
        // A bank or card export: its first rows name merchants, not who it's from.
        if CSVStatement.looksLikeCSV(pages) {
            return Suggestion(title: nil, kind: .statement)
        }
        let pages = pages.map(withoutScreenChrome)
        let text = pages.map(\.text).joined(separator: "\n").lowercased()
        let kind = kind(of: text)

        // A router sticker or a screenshot of one.
        if ["wi-fi password", "wifi password", "wi-fi name", "wifi name", "network name", "ssid", "network key"]
            .contains(where: { text.contains($0) }) {
            return Suggestion(title: "Wi-Fi Network", kind: kind)
        }

        // An ID is named for what it is: "Passport", not the country on top.
        if kind == .identity, let type = identityName(text) {
            return Suggestion(title: type, kind: kind)
        }
        guard let name = name(in: pages) else {
            return Suggestion(title: nil, kind: kind)
        }
        return Suggestion(title: title(name, kind: kind), kind: kind)
    }

    /// A screenshot's status bar ("6:21 PM", the carrier, the battery) and
    /// the Photos bar above a picture ("44 of 84") say nothing about what's in
    /// it, but they're at the top, where names are looked for. Dropped when
    /// a time sits in the top strip, which is how a screenshot looks.
    static func withoutScreenChrome(_ page: RecognizedPage) -> RecognizedPage {
        let time = DayParser.regex("^\\d{1,2}:\\d{2}( ?[ap]m)?$")
        let isScreenshot = page.lines.contains { line in
            guard let box = line.box, box.y < 0.06 else { return false }
            let text = line.text.trimmingCharacters(in: .whitespaces)
            return time.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
        }
        guard isScreenshot else { return page }
        let counter = DayParser.regex("^\\d+ of \\d+$")
        var trimmed = page
        trimmed.lines = page.lines.filter { line in
            guard let box = line.box else { return true }
            if box.y < 0.06 { return false }
            let text = line.text.trimmingCharacters(in: .whitespaces)
            if box.y < 0.15, counter.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
                || ["photos", "back", "done", "edit"].contains(text.lowercased()) {
                return false
            }
            return true
        }
        return trimmed
    }

    /// A voice note is named by its first words: "Spare HDMI cable is in the
    /// hall closet" rather than "Voice note 3".
    static func noteTitle(_ transcript: String) -> String? {
        let words = transcript.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        let firstSentence = transcript.split(whereSeparator: { ".!?".contains($0) }).first.map(String.init) ?? transcript
        var title = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count > 50 {
            title = String(title.prefix(50))
            if let lastSpace = title.lastIndex(of: " ") { title = String(title[..<lastSpace]) }
            title += "…"
        }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    /// Who the document is from: "CVS Pharmacy", "Chase", "Blue Bottle Coffee".
    static func name(in pages: [RecognizedPage]) -> String? {
        guard let first = pages.first else { return nil }
        return knownName(in: first) ?? prominentLine(in: first)
    }

    // MARK: Category

    static func kind(of text: String) -> RecordKind? {
        func count(_ phrases: [String]) -> Int { phrases.count { text.contains($0) } }

        if text.contains("warranty") {
            return .warranty
        }
        // Utility and phone bills print a "statement date" and the last
        // balance too; only card and bank statements print these.
        let cardWords = count(["minimum payment", "new balance", "credit limit", "available credit", "statement period",
                               "closing date", "beginning balance", "ending balance"])
        let billWords = count(["amount due", "due date", "billing period", "service period", "account number", "pay by",
                               "kwh", "therms", "gallons used"])
        if billWords >= 2, cardWords == 0 {
            return .bill
        }
        if text.contains("statement"),
           cardWords > 0 || count(["balance", "payment due"]) > 0 {
            return .statement
        }
        if billWords >= 2 {
            return .bill
        }
        if count(["passport", "driver license", "driver's license", "drivers license", "identification card",
                  "vehicle registration", "registration card", "insurance card", "declarations page",
                  "lease agreement", "residential lease", "id card"]) >= 1 {
            return .identity
        }
        if count(["subtotal", "total", "tax", "change due", "cash", "visa", "mastercard", "debit", "card #",
                  "auth", "approved", "thank you", "receipt", "reg#", "trn#", "cashier", "qty"]) >= 2 {
            return .receipt
        }
        if count(["manual", "instructions", "troubleshooting", "specifications", "safety information"]) >= 2 {
            return .manual
        }
        return nil
    }

    /// What kind of ID or policy: the name it's filed under.
    static func identityName(_ text: String) -> String? {
        let names: [([String], String)] = [
            (["passport"], "Passport"),
            (["driver license", "driver's license", "drivers license"], "Driver's License"),
            (["vehicle registration", "registration card"], "Vehicle Registration"),
            (["insurance card", "declarations page"], "Insurance Card"),
            (["lease agreement", "residential lease"], "Lease"),
            (["identification card", "id card"], "ID Card"),
        ]
        return names.first { $0.0.contains { text.contains($0) } }?.1
    }

    /// "Chase" alone says less than "Chase Statement" in a list of names.
    static func title(_ name: String, kind: RecordKind?) -> String {
        let lower = name.lowercased()
        switch kind {
        case .statement where !lower.contains("statement"): return "\(name) Statement"
        case .warranty where !lower.contains("warranty"): return "\(name) Warranty"
        case .bill where !lower.contains("bill"): return "\(name) Bill"
        default: return name
        }
    }

    // MARK: Known names

    /// Lowercased fragment, then how to write it. Longer fragments first where
    /// one contains another.
    static let knownNames: [(String, String)] = [
        ("cvs", "CVS Pharmacy"), ("walgreens", "Walgreens"), ("rite aid", "Rite Aid"),
        ("target", "Target"), ("walmart", "Walmart"), ("costco", "Costco"), ("sam's club", "Sam's Club"),
        ("trader joe", "Trader Joe's"), ("whole foods", "Whole Foods"), ("safeway", "Safeway"),
        ("kroger", "Kroger"), ("publix", "Publix"), ("aldi", "Aldi"), ("stop & shop", "Stop & Shop"),
        ("wegmans", "Wegmans"), ("h-e-b", "H-E-B"), ("market basket", "Market Basket"),
        ("home depot", "Home Depot"), ("lowe's", "Lowe's"), ("lowes", "Lowe's"), ("ikea", "IKEA"),
        ("best buy", "Best Buy"), ("apple card", "Apple Card"), ("apple store", "Apple Store"),
        ("amazon", "Amazon"), ("starbucks", "Starbucks"), ("dunkin", "Dunkin'"), ("mcdonald", "McDonald's"),
        ("chipotle", "Chipotle"), ("panera", "Panera Bread"), ("chick-fil-a", "Chick-fil-A"),
        ("shell", "Shell"), ("chevron", "Chevron"), ("exxon", "Exxon"), ("mobil", "Mobil"),
        ("sunoco", "Sunoco"), ("speedway", "Speedway"), ("wawa", "Wawa"), ("7-eleven", "7-Eleven"),
        ("chase", "Chase"), ("capital one", "Capital One"), ("american express", "American Express"),
        ("discover", "Discover"), ("citibank", "Citi"), ("bank of america", "Bank of America"),
        ("wells fargo", "Wells Fargo"), ("pg&e", "PG&E"), ("national grid", "National Grid"),
        ("eversource", "Eversource"), ("con edison", "Con Edison"), ("xfinity", "Xfinity"),
        ("comcast", "Comcast"), ("verizon", "Verizon"), ("at&t", "AT&T"), ("t-mobile", "T-Mobile"),
        ("netflix", "Netflix"), ("samsung", "Samsung"), ("sony", "Sony"), ("uber eats", "Uber Eats"), ("uber", "Uber"),
        ("lyft", "Lyft"), ("doordash", "DoorDash"), ("grubhub", "Grubhub"), ("instacart", "Instacart"),
        ("prime video", "Prime Video"), ("google cloud", "Google Cloud"), ("google", "Google"), ("microsoft", "Microsoft"),
        ("apple.com/bill", "Apple"), ("spotify", "Spotify"), ("hulu", "Hulu"), ("steam", "Steam"), ("discord", "Discord"),
        ("patreon", "Patreon"), ("replit", "Replit"), ("vercel", "Vercel"), ("anthropic", "Anthropic"),
        ("supabase", "Supabase"), ("github", "GitHub"), ("wendys", "Wendy's"), ("wendy's", "Wendy's"),
        ("mcdonalds", "McDonald's"), ("burger king", "Burger King"), ("taco bell", "Taco Bell"),
        ("cumberland farms", "Cumberland Farms"), ("exxonmobil", "ExxonMobil"),
    ]

    /// How far down a known name still counts as the document's own.
    static let headerLines = 12

    static func knownName(in page: RecognizedPage) -> String? {
        for line in page.lines.prefix(headerLines) {
            if let name = knownName(inText: line.text) { return name }
        }
        return nil
    }

    /// The known name that appears first, so "DD *DOORDASH CVS" is DoorDash
    /// (the order went through DoorDash) rather than CVS. At the same spot the
    /// longer name wins: "uber eats" over "uber".
    static func knownName(inText text: String) -> String? {
        let lower = text.lowercased()
        var best: (position: Int, length: Int, name: String)?
        for (fragment, name) in knownNames {
            guard let position = position(of: fragment, in: lower) else { continue }
            if best == nil || position < best!.position || (position == best!.position && fragment.count > best!.length) {
                best = (position, fragment.count, name)
            }
        }
        return best?.name
    }

    /// Where `fragment` starts as a word: never mid-word ("eggshell"), and for
    /// short names never followed by more letters either. Longer names may
    /// run on, as card statements print them: "DOORDASHDASHPASS".
    private static func position(of fragment: String, in text: String) -> Int? {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: fragment, range: searchRange) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            let isBoundary = { (c: Character?) in c.map { !$0.isLetter } ?? true }
            if isBoundary(before) && (fragment.count > 5 || isBoundary(after)) {
                return text.distance(from: text.startIndex, to: range.lowerBound)
            }
            searchRange = range.upperBound..<text.endIndex
        }
        return nil
    }

    // MARK: Prominent line

    /// Words that sit at the top of receipts but are never the name.
    static let boilerplate = ["welcome", "receipt", "thank", "customer copy", "merchant copy", "store #",
                              "tel", "phone", "www", "http", ".com", "invoice", "page "]

    static func prominentLine(in page: RecognizedPage) -> String? {
        let candidates = page.lines.enumerated().compactMap { index, line -> (Int, RecognizedLine, String)? in
            guard let cleaned = clean(line.text), isNameLike(cleaned) else { return nil }
            if let box = line.box, box.y > 0.45 { return nil }
            if line.box == nil, index >= headerLines { return nil }
            return (index, line, cleaned)
        }
        // With positions, the tallest; without, the first.
        let best = candidates.max { a, b in
            let ha = a.1.box?.height ?? 0, hb = b.1.box?.height ?? 0
            return ha != hb ? ha < hb : a.0 > b.0
        }
        return best.map { titleCased($0.2) }
    }

    /// Strips decoration OCR picks up around a name: "♥CVS pharmacy*" → "CVS pharmacy".
    static func clean(_ text: String) -> String? {
        // "JIFFY LUBE #2291", "STARBUCKS STORE 10442": the store number isn't the name.
        let numbered = text.replacingOccurrences(of: "\\s+(#\\s*|store\\s*#?\\s*|no\\.?\\s*)\\d+\\s*$", with: "",
                                                 options: [.regularExpression, .caseInsensitive])
        let trimmed = numbered.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let collapsed = trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : String(collapsed.prefix(40))
    }

    static func isNameLike(_ text: String) -> Bool {
        let letters = text.count(where: \.isLetter)
        let digits = text.count(where: \.isNumber)
        guard letters >= 3, digits * 3 < letters else { return false }
        // Addresses and dates start with a number.
        guard let first = text.first, !first.isNumber else { return false }
        let lower = text.lowercased()
        return !boilerplate.contains { lower.contains($0) }
    }

    /// Short words that are words, not initials.
    static let shortWords: Set<String> = ["the", "and", "for", "you", "our", "of", "to", "at", "in", "on", "by",
                                          "its", "new", "old", "inc", "llc", "co", "a", "an", "&", "be", "it", "is", "my"]

    /// "TRADER JOE'S" → "Trader Joe's", but short all-caps initials stay: "CVS".
    static func titleCased(_ text: String) -> String {
        text.split(separator: " ").map { word in
            let w = String(word)
            // Its own capitals, like "JetBlue" or "iPhone": as written.
            if w != w.uppercased(), w != w.lowercased(), w.dropFirst() != w.dropFirst().lowercased() { return w }
            if w.count <= 3, w == w.uppercased(), w.contains(where: \.isLetter),
               !shortWords.contains(w.lowercased()) { return w }
            return w.prefix(1).uppercased() + w.dropFirst().lowercased()
        }.joined(separator: " ")
    }
}

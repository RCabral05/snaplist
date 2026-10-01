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
        let text = pages.map(\.text).joined(separator: "\n").lowercased()
        let kind = kind(of: text)

        guard let name = name(in: pages) else {
            return Suggestion(title: nil, kind: kind)
        }
        return Suggestion(title: title(name, kind: kind), kind: kind)
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
        if text.contains("statement"),
           count(["balance", "payment due", "minimum payment", "statement period", "closing date"]) > 0 {
            return .statement
        }
        if count(["amount due", "due date", "billing period", "service period", "account number", "pay by"]) >= 2 {
            return .bill
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
        ("netflix", "Netflix"), ("samsung", "Samsung"), ("sony", "Sony"), ("uber", "Uber"), ("lyft", "Lyft"),
    ]

    /// How far down a known name still counts as the document's own.
    static let headerLines = 12

    static func knownName(in page: RecognizedPage) -> String? {
        for line in page.lines.prefix(headerLines) {
            let words = line.text.lowercased()
            for (fragment, name) in knownNames where contains(words, word: fragment) {
                return name
            }
        }
        return nil
    }

    /// `fragment` at word boundaries, so "shell" doesn't match "eggshell".
    private static func contains(_ text: String, word fragment: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: fragment, range: searchRange) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            let isBoundary = { (c: Character?) in c.map { !$0.isLetter } ?? true }
            if isBoundary(before) && isBoundary(after) { return true }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
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
        let trimmed = text.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
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
                                          "its", "new", "old", "inc", "llc", "co", "a", "an", "&"]

    /// "TRADER JOE'S" → "Trader Joe's", but short all-caps initials stay: "CVS".
    static func titleCased(_ text: String) -> String {
        text.split(separator: " ").map { word in
            let w = String(word)
            if w.count <= 3, w == w.uppercased(), w.contains(where: \.isLetter),
               !shortWords.contains(w.lowercased()) { return w }
            return w.prefix(1).uppercased() + w.dropFirst().lowercased()
        }.joined(separator: " ")
    }
}

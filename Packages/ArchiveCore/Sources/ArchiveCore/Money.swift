import Foundation

/// An amount in whole cents. Money is never a Double anywhere in the archive:
/// totals are sums of integers, so $0.10 + $0.20 is exactly $0.30.
public struct Money: Hashable, Sendable, Codable {
    public var cents: Int64
    public var currency: String

    public init(cents: Int64, currency: String = "USD") {
        self.cents = cents
        self.currency = currency
    }
}

/// An amount as printed on a line.
struct ParsedAmount: Equatable {
    /// Magnitude, never negative.
    var cents: Int64
    var currency: String?
    /// Printed as negative: "-12.00", "(12.00)" or "12.00 CR".
    var isCredit: Bool
    var range: NSRange
}

enum MoneyParser {
    /// Amounts with two decimals ("41.37", "$1,234.56", "€12,50", "(5.00)",
    /// "12.00 CR"), or whole amounts only when a currency sign makes them
    /// money ("$25"). Quantities like "10.214 GAL" and dates don't match.
    private static let pattern = DayParser.regex(
        "(?<![\\d.,/])(?<neg>[-−(])?\\s?(?<cur>[$€£])?\\s?" +
        "(?:(?<num>\\d{1,3}(?:[,.]\\d{3})+[.,]\\d{2}|\\d+[.,]\\d{2})|(?<whole>(?<=[$€£])\\d+))" +
        // Not a quantity with its unit after it: "(3.50g)", "2.25 lb".
        "(?![\\d.,]*\\d)(?!\\s?(?:g|kg|mg|lbs?|oz|ml|l|gal|ct|pk)\\b)(?<close>\\))?(?:\\s?(?<after>[€£]))?(?:\\s?(?<cr>CR)\\b)?")

    static func amounts(in line: String) -> [ParsedAmount] {
        let ns = line as NSString
        return pattern.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            func group(_ name: String) -> String? {
                let r = m.range(withName: name)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            let cents: Int64
            if let number = group("num") {
                guard let value = parseDecimal(number) else { return nil }
                cents = value
            } else if let whole = group("whole"), let value = Int64(whole) {
                cents = value * 100
            } else {
                return nil
            }
            // "$12.00", or "12,00 €" as Europe prints it.
            let currency = (group("cur") ?? group("after")).map { ["$": "USD", "€": "EUR", "£": "GBP"][$0] ?? "USD" }
            let isCredit = group("neg") != nil || group("cr") != nil
            return ParsedAmount(cents: cents, currency: currency, isCredit: isCredit, range: m.range)
        }
    }

    /// The last separator followed by exactly two digits is the decimal
    /// point; every other separator groups thousands.
    static func parseDecimal(_ text: String) -> Int64? {
        let digits = text.filter(\.isNumber)
        guard digits.count >= 3, let value = Int64(digits) else { return nil }
        return value
    }

    /// "$1,234.56" for display in plain text (tests, messages).
    static func format(_ money: Money) -> String {
        let symbol = ["USD": "$", "EUR": "€", "GBP": "£"][money.currency] ?? "\(money.currency) "
        let sign = money.cents < 0 ? "-" : ""
        let magnitude = abs(money.cents)
        let dollars = String(magnitude / 100)
        var grouped = ""
        for (index, character) in dollars.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        return "\(sign)\(symbol)\(String(grouped.reversed())).\(String(format: "%02lld", magnitude % 100))"
    }
}

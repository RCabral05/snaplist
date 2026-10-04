import Foundation

/// Finds the lines on a page that hold something private, so a shared copy
/// can black them out: card and account numbers, addresses, phone numbers,
/// email addresses, and ID numbers and birth dates. Store names, items,
/// dates and totals stay readable, since they're what the copy is for.
public enum Redactor {
    public enum Reason: String, Sendable {
        case card, account, address, phone, email, idNumber, birthDate, name
        /// One of the person's own words to hide: their name, street, phone.
        case yours
    }

    /// Indexes into `page.lines`, with why each is hidden. `alsoHide` are the
    /// person's own words (their name, street): any line with one is hidden.
    public static func privateLines(_ page: RecognizedPage, alsoHide: [String] = []) -> [(index: Int, reason: Reason)] {
        let own = alsoHide.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { $0.count >= 3 }
        return page.lines.enumerated().compactMap { index, line in
            let lower = line.text.lowercased()
            if own.contains(where: { lower.contains($0) || digitsMatch(lower, $0) }) { return (index, .yours) }
            return reason(for: line.text).map { (index, $0) }
        }
    }

    /// A phone number typed one way and printed another: "401-555-0199" and "(401) 555 0199".
    private static func digitsMatch(_ line: String, _ word: String) -> Bool {
        let wanted = word.filter(\.isNumber)
        return wanted.count >= 7 && line.filter(\.isNumber).contains(wanted)
    }

    static func reason(for text: String) -> Reason? {
        // OCR reads a zero as an O inside numbers: "401-555-019O".
        let text = text.replacingOccurrences(of: "(?<=\\d)[Oo](?=[\\d\\s.-]|$)|(?<=[\\s(.-])[Oo](?=\\d)", with: "0",
                                             options: .regularExpression)
        let lower = text.lowercased()
        let digits = text.filter(\.isNumber)
        func matches(_ regex: NSRegularExpression) -> Bool {
            regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
        }

        if matches(email) { return .email }
        if matches(ssn) || ["ssn", "social security"].contains(where: lower.contains) && digits.count >= 4 { return .idNumber }
        if matches(longNumber) || matches(maskedCard) { return .card }
        if ["visa", "mastercard", "amex", "american express", "discover", "debit", "card #", "card no", "acct #"]
            .contains(where: lower.contains), digits.count >= 4 { return .card }
        if ["date of birth", "dob", "birth date", "born"].contains(where: lower.contains), digits.count >= 4 { return .birthDate }
        if ["passport no", "passport number", "license no", "licence no", "dl ", "dl#", "dl:", "id no", "id #", "id number",
            "member id", "policy number", "policy no", "policy #", "plate", "vin", "guest:", "customer id", "patient id"]
            .contains(where: lower.contains), digits.count >= 4 || text.count(where: \.isUppercase) >= 6 && digits.count >= 2 {
            return .idNumber
        }
        if ["account", "acct", "routing", "member #", "loan"].contains(where: lower.contains), digits.count >= 4 { return .account }
        if matches(phone) { return .phone }
        if matches(phoneLabel), digits.count >= 7 { return .phone }
        if matches(labelledName) { return .name }
        if matches(street) || matches(cityStateZip) { return .address }
        return nil
    }

    /// 12 to 19 digits in a row, spaces or dashes allowed: a card number.
    private static let longNumber = DayParser.regex("(?<!\\d)(?:\\d[ -]?){11,18}\\d(?!\\d)")
    /// "****4421", "XXXX8812".
    private static let maskedCard = DayParser.regex("[*x•]{4,}[ -]?\\d{4}")
    private static let ssn = DayParser.regex("(?<!\\d)\\d{3}-\\d{2}-\\d{4}(?!\\d)")
    private static let phone = DayParser.regex(
        "(?<!\\d)(?:\\+?1[ .-]?)?(?:\\(\\d{3}\\)\\s?|\\d{3}[ .-]?)\\d{3}[ .-]?\\d{4}(?!\\d)")
    /// "Tel", "Phone:", "Ph", "Cell", as words: not the "tel" in "hotel".
    private static let phoneLabel = DayParser.regex("\\b(?:tel|phone|ph|cell|mobile|fax)\\b")
    /// "Name: Jordan Doe", "Customer JORDAN DOE", "Ship to: …", "Dear Jordan,".
    private static let labelledName = DayParser.regex(
        "^\\s*(?:name|customer|customer name|guest|guest name|member|member name|cardholder|card holder|patient|client|"
        + "account holder|ship to|bill to|sold to|deliver to|recipient|attn|dear|insured|owner|driver|employee)\\b[:\\s]+"
        // …but not "Customer copy", "Member savings", "Guest services".
        + "(?!(?:copy|service|services|care|support|savings|rewards|receipt|signature|number|no\\b|id\\b|since|points|count)\\b)[a-z]")
    private static let email = DayParser.regex("[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}")
    /// "444 Quaker Ln.", "1709 Automation Pkwy", "12 Park Ave Apt 4".
    private static let street = DayParser.regex(
        "^\\s*\\d{1,6}\\s+(?:[a-z0-9.'-]+\\s+){0,4}(?:st|street|ave|avenue|rd|road|blvd|boulevard|dr|drive|ln|lane|way|ct|court|pl|place|pkwy|parkway|hwy|highway|cir|circle|ter|terrace|sq|square)\\b")
    /// "Warwick, RI 02886", "SAN JOSE CA 95112".
    private static let cityStateZip = DayParser.regex("[a-z]{2,},?\\s+[a-z]{2}\\s+\\d{5}(?:-\\d{4})?\\b")
}

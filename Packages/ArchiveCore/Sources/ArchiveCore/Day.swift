import Foundation

/// A calendar date with no time or zone: what a receipt or statement prints.
/// Stored as "2026-09-28", which sorts correctly as text.
public struct Day: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Nil for dates that don't exist, like 2/30.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), (1...31).contains(day), (1900...2200).contains(year) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = Self.calendar.date(from: components),
              Self.calendar.component(.day, from: date) == day else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// The day `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year!
        self.month = c.month!
        self.day = c.day!
    }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { iso }

    /// Noon on this day in `calendar`'s zone: safely inside the day for display.
    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    public func adding(days: Int) -> Day {
        let date = Self.calendar.date(byAdding: .day, value: days, to: utcNoon)!
        return Day(date, calendar: Self.calendar)
    }

    /// Whole days from `self` to `other`; negative if `other` is earlier.
    public func days(to other: Day) -> Int {
        Self.calendar.dateComponents([.day], from: utcNoon, to: other.utcNoon).day!
    }

    public static func < (a: Day, b: Day) -> Bool { a.iso < b.iso }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let day = Day(iso: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a day: \(text)"))
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }

    private var utcNoon: Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

/// Both ends included.
public struct DayRange: Hashable, Sendable {
    public var start: Day
    public var end: Day

    public init(_ start: Day, _ end: Day) {
        self.start = start
        self.end = end
    }

    public func contains(_ day: Day) -> Bool { start <= day && day <= end }

    public static func month(_ month: Int, of year: Int) -> DayRange? {
        guard let start = Day(year: year, month: month, day: 1) else { return nil }
        let next = month == 12 ? Day(year: year + 1, month: 1, day: 1)! : Day(year: year, month: month + 1, day: 1)!
        return DayRange(start, next.adding(days: -1))
    }

    public static func year(_ year: Int) -> DayRange? {
        guard let start = Day(year: year, month: 1, day: 1), let end = Day(year: year, month: 12, day: 31) else { return nil }
        return DayRange(start, end)
    }
}

/// Finds dates in printed text.
enum DayParser {
    static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    static func month(named name: String) -> Int? {
        let prefix = name.lowercased().prefix(3)
        return months.firstIndex(of: String(prefix)).map { $0 + 1 }
    }

    private static let monthPattern = "(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\\.?"

    private static let patterns: [(NSRegularExpression, @Sendable (NSTextCheckingResult, String) -> Day?)] = [
        // 2026-09-28
        (regex("(?<!\\d)(\\d{4})-(\\d{1,2})-(\\d{1,2})(?!\\d)"), { m, s in
            Day(year: int(m, 1, s), month: int(m, 2, s), day: int(m, 3, s))
        }),
        // 09/28/2026, 9-28-26 (US order)
        (regex("(?<![\\d/])(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{4}|\\d{2})(?![\\d/])"), { m, s in
            Day(year: fullYear(int(m, 3, s)), month: int(m, 1, s), day: int(m, 2, s))
        }),
        // September 28, 2026 / Sep 28 2026
        (regex("\\b\(monthPattern)\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})\\b"), { m, s in
            guard let month = month(named: string(m, 1, s)) else { return nil }
            return Day(year: int(m, 3, s), month: month, day: int(m, 2, s))
        }),
        // 28 September 2026
        (regex("\\b(\\d{1,2})\\s+\(monthPattern),?\\s+(\\d{4})\\b"), { m, s in
            guard let month = month(named: string(m, 2, s)) else { return nil }
            return Day(year: int(m, 3, s), month: month, day: int(m, 1, s))
        }),
    ]

    /// Every complete date in `text`, in order of appearance.
    static func days(in text: String) -> [(day: Day, range: NSRange)] {
        let ns = text as NSString
        var found: [(Day, NSRange)] = []
        for (regex, build) in patterns {
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard !found.contains(where: { NSIntersectionRange($0.1, match.range).length > 0 }),
                      let day = build(match, text) else { continue }
                found.append((day, match.range))
            }
        }
        return found.sorted { $0.1.location < $1.1.location }
    }

    static func firstDay(in text: String) -> Day? { days(in: text).first?.day }

    private static let yearless = regex("^\\s*(?:(\\d{1,2})/(\\d{1,2})(?![/\\d])|\(monthPattern)\\s+(\\d{1,2})(?![\\d,]*\\s*\\d{4}))")

    /// A statement row's leading date, which may not print a year: "09/02",
    /// "Jul 03", or a full date. Returns the month and day, the year if
    /// present, and how many characters the date took.
    static func leadingDate(in row: String) -> (month: Int, day: Int, year: Int?, length: Int)? {
        let ns = row as NSString
        let whole = NSRange(location: 0, length: ns.length)
        if let (day, range) = days(in: row).first,
           ns.substring(to: range.location).trimmingCharacters(in: .whitespaces).isEmpty {
            return (day.month, day.day, day.year, range.location + range.length)
        }
        guard let m = yearless.firstMatch(in: row, range: whole) else { return nil }
        if m.range(at: 1).location != NSNotFound {
            let month = int(m, 1, row), day = int(m, 2, row)
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }
            return (month, day, nil, m.range.location + m.range.length)
        }
        guard let month = month(named: string(m, 3, row)) else { return nil }
        let day = int(m, 4, row)
        guard (1...31).contains(day) else { return nil }
        return (month, day, nil, m.range.location + m.range.length)
    }

    // MARK: Helpers

    static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func string(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String {
        (s as NSString).substring(with: m.range(at: i))
    }

    private static func int(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> Int {
        Int(string(m, i, s)) ?? 0
    }

    private static func fullYear(_ year: Int) -> Int { year < 100 ? 2000 + year : year }
}

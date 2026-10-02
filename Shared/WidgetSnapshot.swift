import Foundation

/// What the widgets show, written by the app into the App Group container
/// whenever its numbers change. Widgets never open the archive itself: they
/// only see these few totals and dates.
struct WidgetSnapshot: Codable, Sendable {
    struct Category: Codable, Sendable, Hashable {
        var name: String
        var amount: String
        /// 0…1 of the month's total, for a bar.
        var share: Double
    }

    struct Upcoming: Codable, Sendable, Hashable {
        var title: String
        var date: Date
        var amount: String?
        var symbol: String
    }

    struct BudgetLine: Codable, Sendable, Hashable {
        var name: String
        var spent: String
        var limit: String
        var fraction: Double
    }

    var monthLabel: String
    var monthTotal: String
    var categories: [Category]
    var upcoming: [Upcoming]
    var budgets: [BudgetLine]
    /// The theme's accent, so widgets match the app: "ledger", "vault", "clarity".
    var theme: String
    var updated: Date

    static let appGroup = "group.com.rcabral.snaplist"
    static let fileName = "widget.json"

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appending(path: fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() throws {
        guard let url = Self.url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static let placeholder = WidgetSnapshot(
        monthLabel: "September", monthTotal: "$1,248",
        categories: [Category(name: "Eating out", amount: "$412", share: 0.33),
                     Category(name: "Groceries", amount: "$301", share: 0.24),
                     Category(name: "Fuel", amount: "$186", share: 0.15)],
        upcoming: [Upcoming(title: "PG&E Bill due", date: .now.addingTimeInterval(86_400 * 5), amount: "$160.43",
                            symbol: "calendar.badge.clock")],
        budgets: [BudgetLine(name: "Eating out", spent: "$412", limit: "$500", fraction: 0.82)],
        theme: "ledger", updated: .now)
}

/// Links widgets open: snaplist://scan, snaplist://ask, snaplist://spending.
enum SnaplistLink: String, Sendable {
    case scan, ask, spending, home

    var url: URL { URL(string: "snaplist://\(rawValue)")! }
}

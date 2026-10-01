import ArchiveCore
import SwiftUI

/// The few decisions every screen shares: a serif for headings (Apple's New
/// York, so nothing to bundle), one colour per category, and how records are
/// grouped by date.
enum Theme {
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    static let cardRadius: CGFloat = 14

    // Warm paper: cream and white by day, warm charcoal by night. No pure
    // black or white backgrounds, and no system blue.

    /// Amber: deep enough to read as text on cream, brighter on charcoal.
    static let accent = Color(light: 0xB45309, dark: 0xF5B942)
    /// Behind everything.
    static let background = Color(light: 0xF6F1E7, dark: 0x1C1A17)
    /// Cards, rows and fields that sit on the background.
    static let surface = Color(light: 0xFFFDF8, dark: 0x2A2723)
}

extension Color {
    /// One colour for light mode and one for dark, from hex.
    init(light: UInt32, dark: UInt32) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

extension RecordKind {
    /// Muted, earthy colours that sit on cream and charcoal without shouting.
    var tint: Color {
        switch self {
        case .receipt: Color(light: 0x4F7A5C, dark: 0x8FBF9C)    // sage
        case .statement: Color(light: 0x56657A, dark: 0x9FB0C6)  // slate
        case .bill: Color(light: 0xA65A33, dark: 0xE09A72)       // clay
        case .warranty: Color(light: 0x77588A, dark: 0xBBA0CB)   // plum
        case .manual: Color(light: 0x7D6142, dark: 0xC7A57F)     // walnut
        case .document: Color(light: 0x6E6A62, dark: 0xADA79B)   // stone
        case .item: Color(light: 0xA2505F, dark: 0xDC93A1)       // rose
        case .other: Color(light: 0x7A766E, dark: 0x9C978D)      // ash
        }
    }
}

extension View {
    /// A form on the warm background. Its sections set
    /// `.listRowBackground(Theme.surface)` for the rows.
    func warmForm() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}

/// A category as a small coloured capsule: "● Receipt".
struct KindBadge: View {
    let kind: RecordKind

    var body: some View {
        Label(kind.label, systemImage: kind.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(kind.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(kind.tint.opacity(0.14), in: .capsule)
    }
}

/// This Week, Earlier This Month, then one group per month: coarse enough
/// that a group is rarely a single lonely card.
struct DateGroup: Identifiable {
    var title: String
    var records: [Record]
    var id: String { title }

    static func grouping(_ records: [Record], now: Date = .now, calendar: Calendar = .current) -> [DateGroup] {
        var groups: [DateGroup] = []
        for record in records {
            let title = Self.title(for: record.createdAt, now: now, calendar: calendar)
            if groups.last?.title == title {
                groups[groups.count - 1].records.append(record)
            } else {
                groups.append(DateGroup(title: title, records: [record]))
            }
        }
        return groups
    }

    private static func title(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) || calendar.isDateInYesterday(date) {
            return "This Week"
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) { return "Earlier This Month" }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide))
        }
        return date.formatted(.dateTime.month(.wide).year())
    }
}

import ArchiveCore
import SwiftUI

/// What every screen draws with, read from the theme picked in Settings.
/// Views that read these during `body` update by themselves when the theme
/// changes, because `ThemeStore` is observable.
@MainActor
enum Theme {
    static var current: AppTheme { ThemeStore.shared.theme }

    /// Headings and big numbers, in the theme's typeface.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: current.design, weight: current.weight(weight))
    }

    static var cardRadius: CGFloat { current.cardRadius }
    static var accent: Color { current.accent }
    /// Text and icons on an accent fill.
    static var onAccent: Color { current.onAccent }
    /// Behind everything.
    static var background: Color { current.background }
    /// Cards, rows and fields that sit on the background.
    static var surface: Color { current.surface }
    /// Hairlines around cards; clear in themes that don't outline them.
    static var border: Color { current.border }
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
            let title = Self.title(for: record.effectiveDay.date(calendar: calendar), now: now, calendar: calendar)
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

extension SpendCategory {
    /// Earthy like the record colours, distinct enough to stack in a chart.
    var tint: Color {
        switch self {
        case .fuel: Color(light: 0xB45309, dark: 0xF5B942)          // amber
        case .groceries: Color(light: 0x4F7A5C, dark: 0x8FBF9C)     // sage
        case .dining: Color(light: 0xA65A33, dark: 0xE09A72)        // clay
        case .pharmacy: Color(light: 0x3F7F86, dark: 0x86C3C9)      // teal
        case .utilities: Color(light: 0x56657A, dark: 0x9FB0C6)     // slate
        case .subscriptions: Color(light: 0x77588A, dark: 0xBBA0CB) // plum
        case .shopping: Color(light: 0xA2505F, dark: 0xDC93A1)      // rose
        case .travel: Color(light: 0x7D6142, dark: 0xC7A57F)        // walnut
        case .other: Color(light: 0x8A857B, dark: 0x8F8A80)         // ash
        }
    }

    var symbol: String {
        switch self {
        case .fuel: "fuelpump"
        case .groceries: "cart"
        case .dining: "fork.knife"
        case .pharmacy: "cross.case"
        case .utilities: "bolt"
        case .subscriptions: "repeat"
        case .shopping: "bag"
        case .travel: "airplane"
        case .other: "square.grid.2x2"
        }
    }
}

extension TagKind {
    var symbol: String {
        switch self {
        case .person: "person.fill"
        case .place: "mappin.and.ellipse"
        case .tax: "building.columns"
        }
    }

    var tint: Color {
        switch self {
        case .person: Color(light: 0x3F7F86, dark: 0x86C3C9)  // teal
        case .place: Color(light: 0x8A6A1F, dark: 0xD9B661)   // ochre
        case .tax: Color(light: 0x3F6212, dark: 0xA3D977)     // olive
        }
    }

    var label: String {
        switch self {
        case .person: "Person"
        case .place: "Place"
        case .tax: "Tax"
        }
    }
}

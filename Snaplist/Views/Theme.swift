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
}

extension RecordKind {
    var tint: Color {
        switch self {
        case .receipt: .green
        case .statement: .blue
        case .bill: .orange
        case .warranty: .purple
        case .manual: .brown
        case .document: .gray
        case .item: .pink
        case .other: .secondary
        }
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

/// Today, Yesterday, This Week, Earlier This Month, then one group per month.
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
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return "This Week" }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) { return "Earlier This Month" }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide))
        }
        return date.formatted(.dateTime.month(.wide).year())
    }
}

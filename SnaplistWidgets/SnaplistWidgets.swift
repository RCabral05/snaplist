import SwiftUI
import WidgetKit

@main
struct SnaplistWidgets: WidgetBundle {
    var body: some Widget {
        MonthWidget()
        ComingUpWidget()
        QuickAddWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app reloads widgets when its numbers change; the hourly refresh
        // only moves "in 3 days" along.
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

/// The app's accent for the theme in use.
func accent(_ theme: String?) -> Color {
    switch theme {
    case "vault": Color(red: 0.37, green: 0.92, blue: 0.83)
    case "clarity": Color(red: 0.11, green: 0.27, blue: 0.85)
    default: Color(red: 0.60, green: 0.20, blue: 0.07)
    }
}

// MARK: This month

struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "month", provider: SnapshotProvider()) { entry in
            MonthView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(SnaplistLink.spending.url)
        }
        .configurationDisplayName("This Month")
        .description("What you've spent this month, by category or against your budgets.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct MonthView: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot {
            switch family {
            case .accessoryInline:
                Text("\(snapshot.monthLabel): \(snapshot.monthTotal)").privacySensitive()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.monthLabel).font(.caption2).foregroundStyle(.secondary)
                    Text(snapshot.monthTotal).font(.headline).privacySensitive()
                    if let first = snapshot.budgets.first {
                        Gauge(value: min(1, first.fraction)) { Text(first.name) }
                            .gaugeStyle(.accessoryLinearCapacity)
                    } else if let first = snapshot.categories.first {
                        Text("\(first.name) \(first.amount)").font(.caption2).privacySensitive()
                    }
                }
            case .systemMedium:
                HStack(alignment: .top, spacing: 16) {
                    total(snapshot)
                    VStack(alignment: .leading, spacing: 8) {
                        if snapshot.budgets.isEmpty {
                            ForEach(snapshot.categories.prefix(3), id: \.self) { bar($0.name, $0.amount, $0.share, snapshot) }
                        } else {
                            ForEach(snapshot.budgets.prefix(3), id: \.self) { bar($0.name, "\($0.spent) of \($0.limit)", $0.fraction, snapshot) }
                        }
                    }
                }
            default:
                VStack(alignment: .leading) {
                    total(snapshot)
                    Spacer()
                    if let first = snapshot.categories.first {
                        bar(first.name, first.amount, first.share, snapshot)
                    }
                }
            }
        } else {
            Text("Open Snaplist to see this month.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func total(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.monthLabel).font(.caption).foregroundStyle(.secondary)
            Text(snapshot.monthTotal)
                .font(.system(.title2, design: snapshot.theme == "ledger" ? .serif : .rounded, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .privacySensitive()
        }
    }

    private func bar(_ name: String, _ amount: String, _ share: Double, _ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.caption2.weight(.medium)).lineLimit(1)
                Spacer(minLength: 4)
                Text(amount).font(.caption2).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(accent(snapshot.theme).opacity(0.18))
                    Capsule().fill(share >= 1 ? Color.red : accent(snapshot.theme))
                        .frame(width: geometry.size.width * min(1, max(0.03, share)))
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: Coming up

struct ComingUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "comingUp", provider: SnapshotProvider()) { entry in
            ComingUpView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(SnaplistLink.home.url)
        }
        .configurationDisplayName("Coming Up")
        .description("Bills due, renewals, return windows and warranties ending.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct ComingUpView: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let items = (snapshot?.upcoming ?? []).filter { $0.date >= Calendar.current.startOfDay(for: .now) }
        if let first = items.first {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label(first.title, systemImage: first.symbol).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(first.date, style: .relative).font(.caption2)
                    if let amount = first.amount { Text(amount).font(.caption2).privacySensitive() }
                }
            default:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Coming up").font(.caption.weight(.semibold)).foregroundStyle(accent(snapshot?.theme))
                    ForEach(items.prefix(family == .systemMedium ? 3 : 2), id: \.self) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.symbol).foregroundStyle(accent(snapshot?.theme)).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.caption.weight(.medium)).lineLimit(1)
                                Text(item.date, format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if let amount = item.amount, family == .systemMedium {
                                Text(amount).font(.caption.weight(.semibold)).privacySensitive()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "checkmark.circle").foregroundStyle(accent(snapshot?.theme))
                Text("Nothing due soon").font(.caption.weight(.medium))
            }
        }
    }
}

// MARK: Quick add

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "quickAdd", provider: SnapshotProvider()) { entry in
            QuickAddView(theme: entry.snapshot?.theme)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Scan and Ask")
        .description("Scan a receipt or ask a question in one tap.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct QuickAddView: View {
    let theme: String?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "doc.viewfinder").font(.title2)
            }
            .widgetURL(SnaplistLink.scan.url)
            .accessibilityLabel("Scan with Snaplist")
        } else {
            VStack(spacing: 8) {
                Link(destination: SnaplistLink.scan.url) {
                    Label("Scan", systemImage: "doc.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(accent(theme), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(theme == "vault" ? Color.black : Color.white)
                }
                Link(destination: SnaplistLink.ask.url) {
                    Label("Ask", systemImage: "sparkle.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(accent(theme).opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(accent(theme))
                }
            }
        }
    }
}

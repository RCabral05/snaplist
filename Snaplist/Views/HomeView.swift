import ArchiveCore
import SwiftUI

/// The first tab: this month at a glance, what's coming up, what was added
/// lately, and a place to ask. Every number comes from ArchiveCore.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AddFlow.self) private var addFlow

    var showSettings: () -> Void
    /// Hands a question to the Ask tab.
    var ask: (String) -> Void
    var open: (MainTabs.Tab) -> Void

    @State private var question = ""
    @State private var overview: SpendingOverview?
    @State private var comingUp: [ComingUp] = []
    @State private var budgets: [BudgetStatus] = []
    @State private var inventory: InventorySummary?
    @State private var hasTaxRecords = false
    @State private var changes: [PriceChange] = []
    @State private var collections: [Collection] = []
    @State private var isAddingCollection = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if !model.hasLoaded {
                    Color.clear
                } else if model.records.isEmpty {
                    WelcomeView(canScan: addFlow.canScan, scan: { addFlow.isScanning = true },
                                choosePhotos: { addFlow.isPickingPhotos = true },
                                importFiles: { addFlow.isPickingFiles = true })
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        askField
                        if let month = overview?.months.last(where: { $0.count > 0 }) {
                            MonthCard(month: month, overview: overview!) { open(.spending) }
                        }
                        if !budgets.isEmpty {
                            budgetsSection
                        }
                        if !changes.isEmpty {
                            changesSection
                        }
                        if !comingUp.isEmpty {
                            comingUpSection
                        }
                        collectionsSection
                        recentSection
                        toolsSection
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RecordListView.Destination.self) { destination in
                RecordDetailView(record: destination.record, focusPage: destination.pagePosition)
            }
            // Records change as their text is read, not only when added.
            .task(id: model.derivedRevision) { load() }
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.footnote.weight(.medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text("Snaplist")
                    .font(Theme.display(.largeTitle, weight: .bold))
            }
            Spacer()
            Button(action: showSettings) {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: .circle)
                    .overlay(Circle().strokeBorder(Theme.border))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 12)
    }

    private var askField: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass").foregroundStyle(Theme.accent)
            TextField("Ask or search: “gas last month”", text: $question)
                .submitLabel(.search)
                .onSubmit(submit)
                .accessibilityIdentifier("home-ask")
            if !question.isEmpty {
                Button("Ask", action: submit)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }

    private var comingUpSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coming up").font(Theme.display(.title3))
            VStack(spacing: 0) {
                ForEach(Array(comingUp.prefix(4).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 64) }
                    NavigationLink(value: RecordListView.Destination(record: item.record)) {
                        ComingUpRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        }
    }

    /// Bills and subscriptions that cost something different from last time.
    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Changes").font(Theme.display(.title3))
            VStack(spacing: 0) {
                ForEach(Array(changes.prefix(3).enumerated()), id: \.element.id) { index, change in
                    if index > 0 { Divider().padding(.leading, 58) }
                    NavigationLink { PriceChangeView(change: change) } label: { PriceChangeRow(change: change) }
                        .buttonStyle(.plain)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Collections").font(Theme.display(.title3))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(collections) { collection in
                        NavigationLink { CollectionView(collectionId: collection.id) } label: { CollectionCard(collection: collection) }
                            .buttonStyle(.plain)
                    }
                    Button { isAddingCollection = true } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "plus").font(.title3).foregroundStyle(Theme.accent)
                            Text(collections.isEmpty ? "Car, Home…" : "New").font(.subheadline.weight(.semibold))
                        }
                        .padding(14)
                        .frame(width: 110, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollClipDisabled()
        }
        .sheet(isPresented: $isAddingCollection) {
            CollectionEditor(collection: Collection(name: "", symbol: "folder", keywords: []), isNew: true)
        }
    }

    private var budgetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Budgets this month").font(Theme.display(.title3))
                Spacer()
                Button("Spending") { open(.spending) }.font(.subheadline.weight(.semibold))
            }
            BudgetBars(statuses: Array(budgets.sorted { $0.fraction > $1.fraction }.prefix(3)))
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        }
    }

    /// The home inventory, IDs and policies, and the tax report, one tap from Home.
    private var toolsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            NavigationLink {
                ImportantDocumentsView()
            } label: {
                tool("IDs & policies", "person.text.rectangle", idsDetail)
            }
            NavigationLink {
                ThingsView()
            } label: {
                tool("Things", "sofa",
                     inventory.map { $0.count == 0 ? "What you own" : "\($0.count) · \(Money(cents: $0.totalCents, currency: $0.currency).formattedWhole)" } ?? "What you own")
            }
            NavigationLink {
                TaxReportView()
            } label: {
                tool("Tax report", "building.columns", hasTaxRecords ? "Ready to export" : "Mark records + Tax")
            }
        }
        .buttonStyle(.plain)
    }

    /// "Passport expires in 40 days", else how many there are.
    private var idsDetail: String {
        let documents = model.importantDocuments()
        let today = Day(.now)
        if let soon = documents.first(where: { ($0.expires.map { today.days(to: $0) } ?? 999) <= 90 }), let expires = soon.expires {
            let days = today.days(to: expires)
            return days < 0 ? "\(soon.record.title) expired" : "\(soon.record.title) in \(days)d"
        }
        return documents.isEmpty ? "Passport, licence…" : "\(documents.count) saved"
    }

    private func tool(_ title: String, _ symbol: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Theme.accent)
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recently added").font(Theme.display(.title3))
                Spacer()
                Button("See All") { open(.library) }
                    .font(.subheadline.weight(.semibold))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(recent) { record in
                        NavigationLink(value: RecordListView.Destination(record: record)) {
                            RecordCard(record: record, total: model.totals[record.id])
                                .frame(width: 108)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    /// Newest added first, whatever date they're about.
    private var recent: [Record] {
        Array(model.records.sorted { $0.createdAt > $1.createdAt }.prefix(10))
    }

    private func submit() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        question = ""
        ask(text)
    }

    private func load() {
        overview = model.spendingOverview()
        let today = Day(.now)
        let horizon = today.adding(days: 30)
        budgets = model.budgetStatus()
        changes = model.priceChanges()
        collections = model.collections()
        inventory = model.inventorySummary()
        hasTaxRecords = !model.taxYears().isEmpty
        var items = model.upcomingDates().filter { $0.day <= horizon.addingMonths(12) }.map { date in
            ComingUp(id: date.id, record: date.record, day: date.day, amount: date.amount,
                     title: date.title, symbol: date.symbol, tint: date.record.kind.tint)
        }
        for charge in model.recurringCharges() where charge.nextExpected >= today && charge.nextExpected <= horizon {
            items.append(ComingUp(id: charge.id, record: charge.latest.record, day: charge.nextExpected,
                                  amount: Money(cents: charge.typicalCents, currency: charge.currency),
                                  title: "\(charge.merchant) renews", symbol: "repeat",
                                  tint: charge.category.tint))
        }
        comingUp = items.sorted { $0.day < $1.day }
    }
}

/// A bill, warranty or renewal ahead.
struct ComingUp: Identifiable {
    var id: String
    var record: Record
    var day: Day
    var amount: Money?
    var title: String
    var symbol: String
    var tint: Color
}

private struct ComingUpRow: View {
    let item: ComingUp

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(item.day.date(), format: .dateTime.month(.abbreviated))
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                Text("\(item.day.day)")
                    .font(Theme.display(.headline, weight: .bold))
            }
            .foregroundStyle(item.tint)
            .frame(width: 40, height: 40)
            .background(item.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(relative).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let amount = item.amount {
                Text(amount.formatted).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var relative: String {
        let days = Day(.now).days(to: item.day)
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2..<14: return "In \(days) days"
        default: return item.day.date().formatted(date: .abbreviated, time: .omitted)
        }
    }
}

/// The latest month with spending: total, change from the month before,
/// six months of bars and the top categories. Tapping opens Spending.
private struct MonthCard: View {
    let month: MonthSpending
    let overview: SpendingOverview
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(month.label) spending").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    if let change {
                        Text(change)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(Money(cents: month.totalCents, currency: overview.currency).formatted)
                    .font(Theme.display(.largeTitle, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                bars
                HStack(spacing: 14) {
                    ForEach(top, id: \.key) { entry in
                        HStack(spacing: 6) {
                            Circle().fill(entry.key.tint).frame(width: 8, height: 8)
                            Text("\(entry.key.label) \(Money(cents: entry.value, currency: overview.currency).formattedWhole)")
                                .lineLimit(1)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius + 4))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius + 4).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Spending")
    }

    /// The six calendar months ending with this one, empty ones included,
    /// so a short history doesn't draw two giant bars.
    private var recentMonths: [MonthSpending] {
        (0..<6).reversed().map { back in
            let start = month.range.start.addingMonths(-back)
            if let found = overview.months.first(where: { $0.range.start == start }) { return found }
            let range = DayRange.month(start.month, of: start.year) ?? month.range
            return MonthSpending(range: range, label: "", totalCents: 0, byCategory: [:], count: 0)
        }
    }

    private var bars: some View {
        let months = recentMonths
        let largest = max(1, months.map(\.totalCents).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(months) { item in
                RoundedRectangle(cornerRadius: 4)
                    .fill(item.id == month.id ? Theme.accent : Theme.accent.opacity(0.18))
                    .frame(height: max(4, 56 * CGFloat(max(0, item.totalCents)) / CGFloat(largest)))
            }
        }
        .frame(height: 56, alignment: .bottom)
        .accessibilityHidden(true)
    }

    /// The biggest named categories; "Other" says nothing here.
    private var top: [(key: SpendCategory, value: Int64)] {
        Array(month.byCategory.filter { $0.value > 0 && $0.key != .other }.sorted { $0.value > $1.value }.prefix(3))
    }

    /// "8% less than August"
    private var change: String? {
        guard let index = overview.months.firstIndex(where: { $0.id == month.id }), index > 0 else { return nil }
        let previous = overview.months[index - 1]
        // A month with only a receipt or two isn't a fair comparison.
        guard previous.totalCents > 0, previous.count >= 10, month.count >= 10 else { return nil }
        let percent = Int((Double(month.totalCents - previous.totalCents) / Double(previous.totalCents) * 100).rounded())
        guard abs(percent) <= 150 else { return nil }
        let name = previous.label.components(separatedBy: " ").first ?? previous.label
        if percent == 0 { return "Same as \(name)" }
        return percent < 0 ? "\(-percent)% less than \(name)" : "\(percent)% more than \(name)"
    }
}

extension Money {
    /// "$412", for labels where cents are noise.
    var formattedWhole: String {
        (Decimal(cents) / 100).formatted(.currency(code: currency).precision(.fractionLength(0)))
    }
}

extension UpcomingDate {
    /// "PG&E Bill due", "Samsung TV warranty ends", "Return Best Buy by".
    var title: String {
        switch kind {
        case .billDue: "\(record.title) due"
        case .warrantyEnds: "\(record.title) warranty ends"
        case .returnBy: "Return \(record.title) by"
        case .renewal: "\(record.title) expires"
        }
    }

    var symbol: String {
        switch kind {
        case .billDue: "calendar.badge.clock"
        case .warrantyEnds: "checkmark.shield"
        case .returnBy: "arrow.uturn.backward"
        case .renewal: "person.text.rectangle"
        }
    }
}

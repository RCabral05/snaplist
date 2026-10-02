import ArchiveCore
import Charts
import SwiftUI

/// Spending month by month, what repeats, and what's coming up. Every number
/// is a sum of stored amounts done by ArchiveCore; tapping one shows the
/// amounts behind it.
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var overview: SpendingOverview?
    @State private var recurring: [RecurringCharge] = []
    @State private var upcoming: [UpcomingDate] = []
    @State private var budgets: [BudgetStatus] = []
    @State private var isEditingBudgets = false
    @State private var selectedMonth: Day?
    /// False when Spending is a tab rather than a sheet.
    var showsDone = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let overview, !overview.months.isEmpty {
                        MonthChart(overview: overview, selection: $selectedMonth)
                        if let month = selected(in: overview) {
                            CategoryBreakdown(month: month, currency: overview.currency)
                        }
                    } else if overview != nil {
                        ContentUnavailableView("No spending yet", systemImage: "chart.bar",
                                               description: Text("Import a card statement or scan a receipt, and its amounts show up here by month."))
                    }
                    budgetsSection
                    if !recurring.isEmpty {
                        RecurringSection(charges: recurring)
                    }
                    if !upcoming.isEmpty {
                        UpcomingSection(dates: upcoming)
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Spending")
            .navigationBarTitleDisplayMode(showsDone ? .inline : .large)
            .navigationDestination(for: RecordListView.Destination.self) { destination in
                RecordDetailView(record: destination.record, focusPage: destination.pagePosition)
            }
            .navigationDestination(for: SpendingQuery.self) { query in
                AnswerScreen(query: query)
            }
            .navigationDestination(for: RecurringCharge.self) { charge in
                RecurringDetail(charge: charge)
            }
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .task(id: model.derivedRevision) { load() }
        }
    }

    private var budgetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Budgets").font(Theme.display(.title3))
                Spacer()
                Button(budgets.isEmpty ? "Set Up" : "Edit") { isEditingBudgets = true }
                    .font(.subheadline.weight(.semibold))
            }
            if budgets.isEmpty {
                Text("Set a monthly limit for eating out, groceries or everything, and see how this month is going.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let (statuses, month) = shownBudgets
                BudgetBars(statuses: statuses)
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                Text(budgetCaption(month))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isEditingBudgets) { BudgetEditor() }
    }

    /// Budgets against the month picked on the chart, so the bars match the
    /// total above them; this month's when nothing's been spent yet.
    private var shownBudgets: ([BudgetStatus], MonthSpending?) {
        guard let overview, let month = selected(in: overview) else { return (budgets, nil) }
        return (month.budgetStatus(budgets.map(\.budget), currency: overview.currency), month)
    }

    private func budgetCaption(_ month: MonthSpending?) -> String {
        let thisMonth = Day(.now)
        guard let month, !(month.range.start.year == thisMonth.year && month.range.start.month == thisMonth.month) else {
            return "This month, \(thisMonth.date().formatted(.dateTime.month(.wide))). Statements arrive after a month ends, so until then only receipts and bills count."
        }
        return "\(month.label), the month picked above. Tap another month to see its budgets."
    }

    private func selected(in overview: SpendingOverview) -> MonthSpending? {
        overview.months.first { $0.range.start == selectedMonth } ?? overview.months.last
    }

    private func load() {
        overview = model.spendingOverview()
        recurring = model.recurringCharges()
        upcoming = model.upcomingDates()
        budgets = model.budgetStatus()
    }
}

/// Bars per month, stacked by category. Tap a bar to pick its month.
private struct MonthChart: View {
    let overview: SpendingOverview
    @Binding var selection: Day?

    private var xDomain: ClosedRange<Date> {
        let last = overview.months.last?.range.start ?? Day(.now)
        let first = min(overview.months.first?.range.start ?? last, last.addingMonths(-5))
        return first.date()...last.addingMonths(1).date()
    }

    var body: some View {
        let selected = selection ?? overview.months.last?.range.start
        VStack(alignment: .leading, spacing: 12) {
            if let month = overview.months.first(where: { $0.range.start == selected }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(month.label).font(.subheadline).foregroundStyle(.secondary)
                    Text(Money(cents: month.totalCents, currency: overview.currency).formatted)
                        .font(Theme.display(.largeTitle, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(month.count == 1 ? "1 amount" : "\(month.count) amounts")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(overview.months) { month in
                    ForEach(SpendCategory.allCases, id: \.self) { category in
                        let cents = max(0, month.byCategory[category] ?? 0)
                        if cents > 0 {
                            BarMark(x: .value("Month", month.range.start.date(), unit: .month),
                                    y: .value("Spent", Double(cents) / 100))
                                .foregroundStyle(by: .value("Category", category.label))
                                .opacity(month.range.start == selected ? 1 : 0.45)
                                .cornerRadius(3)
                        }
                    }
                }
            }
            // At least six months wide, so two months of data aren't two giant bars.
            .chartXScale(domain: xDomain)
            .chartForegroundStyleScale(domain: SpendCategory.allCases.map(\.label),
                                       range: SpendCategory.allCases.map(\.tint))
            .chartLegend(.hidden)
            .chartXAxis {
                // Each month with spending by name; a stride skipped the first.
                AxisMarks(values: overview.months.map { $0.range.start.date() }) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount, format: .currency(code: overview.currency).precision(.fractionLength(0)))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plot = proxy.plotFrame else { return }
                            let x = location.x - geometry[plot].origin.x
                            guard let date: Date = proxy.value(atX: x) else { return }
                            let day = Day(date)
                            if let month = overview.months.first(where: { $0.range.contains(day) }) {
                                withAnimation(.snappy) { selection = month.range.start }
                            }
                        }
                }
            }
            .frame(height: 200)
            .accessibilityLabel("Spending by month")
        }
        .padding()
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// The selected month's categories, largest first, each leading to its amounts.
private struct CategoryBreakdown: View {
    let month: MonthSpending
    let currency: String

    var body: some View {
        let rows = month.byCategory.filter { $0.value != 0 }.sorted { $0.value > $1.value }
        let largest = max(1, rows.first?.value ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            Text("By category").font(Theme.display(.title3))
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
                    if index > 0 { Divider().padding(.leading, 52) }
                    NavigationLink(value: SpendingQuery(categories: [row.key], range: month.range, rangeLabel: month.label)) {
                        HStack(spacing: 12) {
                            Image(systemName: row.key.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(row.key.tint)
                                .frame(width: 28, height: 28)
                                .background(row.key.tint.opacity(0.14), in: .circle)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(row.key.label).font(.subheadline)
                                    Spacer()
                                    Text(Money(cents: row.value, currency: currency).formatted)
                                        .font(.subheadline.weight(.medium)).monospacedDigit()
                                }
                                GeometryReader { geometry in
                                    Capsule().fill(row.key.tint.opacity(0.8))
                                        .frame(width: max(4, geometry.size.width * CGFloat(max(0, row.value)) / CGFloat(largest)))
                                }
                                .frame(height: 4)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }
}

/// Subscriptions and other charges that repeat.
private struct RecurringSection: View {
    let charges: [RecurringCharge]

    var body: some View {
        let currency = charges.first?.currency ?? "USD"
        let yearly = charges.filter { $0.currency == currency }.reduce(Int64(0)) { $0 + $1.yearlyCents }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Repeating charges").font(Theme.display(.title3))
                Spacer()
                Text("\(Money(cents: yearly, currency: currency).formatted)/yr")
                    .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(charges.enumerated()), id: \.element.id) { index, charge in
                    if index > 0 { Divider().padding(.leading, 52) }
                    NavigationLink(value: charge) {
                        HStack(spacing: 12) {
                            Image(systemName: charge.category.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(charge.category.tint)
                                .frame(width: 28, height: 28)
                                .background(charge.category.tint.opacity(0.14), in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(charge.merchant).font(.subheadline).lineLimit(1)
                                Text("Next around \(charge.nextExpected.date().formatted(.dateTime.month(.abbreviated).day()))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Money(cents: charge.typicalCents, currency: charge.currency).formatted)
                                    .font(.subheadline.weight(.medium)).monospacedDigit()
                                Text(charge.cadence == .monthly ? "monthly" : "yearly")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            Label("Found from charges that come back each month or year at about the same price.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Bills due and warranties ending, soonest first.
private struct UpcomingSection: View {
    let dates: [UpcomingDate]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coming up").font(Theme.display(.title3))
            VStack(spacing: 0) {
                ForEach(Array(dates.prefix(8).enumerated()), id: \.element.id) { index, date in
                    if index > 0 { Divider().padding(.leading, 52) }
                    NavigationLink(value: RecordListView.Destination(record: date.record)) {
                        HStack(spacing: 12) {
                            Image(systemName: date.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(date.record.kind.tint)
                                .frame(width: 28, height: 28)
                                .background(date.record.kind.tint.opacity(0.14), in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(date.record.title).font(.subheadline).lineLimit(1)
                                Text("\(date.title) \(date.day.date().formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let amount = date.amount {
                                Text(amount.formatted).font(.subheadline.weight(.medium)).monospacedDigit()
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }
}

/// Every charge of one repeating payment.
private struct RecurringDetail: View {
    let charge: RecurringCharge

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(charge.cadence == .monthly ? "Every month" : "Every year")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(Money(cents: charge.typicalCents, currency: charge.currency).formatted)
                        .font(Theme.display(.largeTitle, weight: .bold)).monospacedDigit()
                    Text("About \(Money(cents: charge.yearlyCents, currency: charge.currency).formatted) a year at this price. Next expected around \(charge.nextExpected.date().formatted(date: .long, time: .omitted)).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(charge.charges.reversed().enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading) }
                        NavigationLink(value: RecordListView.Destination(record: item.record, pagePosition: item.transaction.pagePosition)) {
                            CountedRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(charge.merchant)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A spending question's full answer, on its own screen.
struct AnswerScreen: View {
    @Environment(AppModel.self) private var model
    let query: SpendingQuery
    @State private var result: AskResult?

    var body: some View {
        ScrollView {
            if let result {
                AnswerView(result: result, reask: { self.result = model.answer($0) }, decided: {
                    if case .spending(let shown) = self.result { self.result = model.answer(shown.query) }
                })
                    .padding()
            }
        }
        .background(Theme.background)
        .navigationTitle(query.categories.first?.label ?? "Spending")
        .navigationBarTitleDisplayMode(.inline)
        .task { result = model.answer(query) }
    }
}

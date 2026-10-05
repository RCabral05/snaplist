import ArchiveCore
import SwiftUI

// MARK: Monthly recap

/// Last month at a glance: the total against the month before, where it
/// went, the biggest purchases, what renewed, what changed price, and pairs
/// counted once that are worth a look.
struct RecapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let range: DayRange

    @State private var recap: MonthlyRecap?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let recap {
                    VStack(alignment: .leading, spacing: 24) {
                        headline(recap)
                        categories(recap)
                        if !recap.biggest.isEmpty {
                            list("Biggest purchases", recap.biggest)
                        }
                        if !recap.renewals.isEmpty {
                            list("Renewed · \(money(recap.renewalsCents, recap))", recap.renewals)
                        }
                        if !recap.priceChanges.isEmpty {
                            section("Price changes") {
                                VStack(spacing: 0) {
                                    ForEach(Array(recap.priceChanges.enumerated()), id: \.element.id) { index, change in
                                        if index > 0 { Divider().padding(.leading) }
                                        NavigationLink(value: RecordListView.Destination(record: change.latest.record)) {
                                            PriceChangeRow(change: change)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .card()
                            }
                        }
                        if !recap.toReview.isEmpty {
                            section("Worth a look") {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(recap.toReview.count == 1
                                         ? "1 purchase looked like it appeared twice, so it was counted once. Check it's the same one."
                                         : "\(recap.toReview.count) purchases looked like they appeared twice, so each was counted once. Check they're the same.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                    ForEach(recap.toReview) { pair in
                                        DuplicateCard(duplicate: pair) { isSame in
                                            model.decide(pair, isSame: isSame)
                                            load()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                } else if loaded {
                    ContentUnavailableView("Nothing spent in \(QuestionParser.monthLabel(range.start.month, range.start.year))",
                                           systemImage: "calendar",
                                           description: Text("Add that month's receipts or statement and its recap shows up here."))
                }
            }
            .background(Theme.background)
            .navigationTitle("\(QuestionParser.monthLabel(range.start.month, range.start.year)) Recap")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: RecordListView.Destination.self) { destination in
                RecordDetailView(record: destination.record, focusPage: destination.pagePosition)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: model.derivedRevision) { load() }
            .paywallSheet()
        }
    }

    private func load() {
        recap = model.monthlyRecap(for: range)
        loaded = true
    }

    private func money(_ cents: Int64, _ recap: MonthlyRecap) -> String {
        Money(cents: cents, currency: recap.currency).formatted
    }

    private func headline(_ recap: MonthlyRecap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Spent in \(recap.month.label)").font(.subheadline).foregroundStyle(.secondary)
            Text(money(recap.month.totalCents, recap))
                .font(Theme.display(.largeTitle, weight: .bold)).monospacedDigit()
            if let delta = recap.deltaCents, let previous = recap.previous, previous.totalCents > 0 {
                let percent = Int((Double(abs(delta)) / Double(previous.totalCents) * 100).rounded())
                Text(delta == 0 ? "Same as \(previous.label)"
                     : "\(money(abs(delta), recap)) \(delta > 0 ? "more" : "less") than \(previous.label) (\(percent)%)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(delta > 0 ? Color.orange : Color.green)
            }
            Text(recap.month.count == 1 ? "From 1 amount" : "From \(recap.month.count) amounts")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func categories(_ recap: MonthlyRecap) -> some View {
        section("Where it went") {
            VStack(spacing: 12) {
                let largest = recap.categories.first?.cents ?? 1
                ForEach(recap.categories, id: \.category) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Label(entry.category.label, systemImage: entry.category.symbol).font(.subheadline)
                            Spacer()
                            Text(money(entry.cents, recap)).font(.subheadline.weight(.medium)).monospacedDigit()
                        }
                        GeometryReader { geometry in
                            Capsule().fill(entry.category.tint)
                                .frame(width: max(6, geometry.size.width * CGFloat(entry.cents) / CGFloat(max(largest, 1))))
                        }
                        .frame(height: 6)
                    }
                }
            }
            .padding(16)
            .card()
        }
    }

    private func list(_ title: String, _ items: [Counted]) -> some View {
        section(title) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading) }
                    NavigationLink(value: RecordListView.Destination(record: item.record, pagePosition: item.transaction.pagePosition)) {
                        CountedRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.display(.title3))
            content()
        }
    }
}

// MARK: Statement check

/// On a statement: charges with no receipt, returns that never came back,
/// charges that just started repeating, and price changes.
struct StatementCheckSection: View {
    @Environment(AppModel.self) private var model
    let record: Record

    @State private var check: StatementCheck?
    @State private var showsAllWithoutReceipt = false

    var body: some View {
        Group {
            if let check {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Statement check").font(Theme.display(.title3))
                    VStack(alignment: .leading, spacing: 10) {
                        summary(check)
                        ForEach(check.missingRefunds) { item in
                            finding("arrow.uturn.backward.circle.fill", .orange,
                                    "\(item.transaction.money.formatted) return at \(item.record.title) isn't on this statement",
                                    "Returned \(item.day.date().formatted(.dateTime.month(.abbreviated).day())). Refunds can take a week or two; if it's been longer, ask the store.",
                                    record: item.record)
                        }
                        ForEach(check.newRecurring) { charge in
                            finding("repeat.circle.fill", .blue,
                                    "\(charge.merchant) is charging you \(charge.cadence == .monthly ? "every month" : "every year")",
                                    "\(Money(cents: charge.typicalCents, currency: charge.currency).formatted) each time, starting \(charge.charges[0].day.date().formatted(.dateTime.month(.abbreviated).day())). New since recently: make sure you meant to sign up.",
                                    record: charge.latest.record)
                        }
                        ForEach(check.priceChanges) { change in
                            NavigationLink(value: RecordListView.Destination(record: change.latest.record)) {
                                PriceChangeRow(change: change)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .card()

                    if !check.withoutReceipt.isEmpty {
                        DisclosureGroup(isExpanded: $showsAllWithoutReceipt) {
                            VStack(spacing: 0) {
                                ForEach(Array(check.withoutReceipt.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Divider() }
                                    HStack {
                                        Text(item.transaction.merchant).font(.subheadline).lineLimit(1)
                                        Spacer()
                                        Text(item.day.date(), format: .dateTime.month(.abbreviated).day())
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(item.transaction.money.formatted).font(.subheadline).monospacedDigit()
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            Text("No receipt saved (\(check.withoutReceipt.count))").font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .task(id: "\(record.id)-\(model.derivedRevision)") { check = model.statementCheck(record.id) }
    }

    private func summary(_ check: StatementCheck) -> some View {
        let total = check.matched + check.withoutReceipt.count
        return Label {
            Text(check.isAllClear
                 ? "Nothing unusual. \(check.matched) of \(total) charges match a saved receipt or bill."
                 : "\(check.matched) of \(total) charges match a saved receipt or bill. Worth a look:")
                .font(.subheadline)
        } icon: {
            Image(systemName: check.isAllClear ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(check.isAllClear ? Color.green : Color.orange)
        }
    }

    private func finding(_ symbol: String, _ tint: Color, _ title: String, _ detail: String, record: Record) -> some View {
        NavigationLink(value: RecordListView.Destination(record: record)) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                    Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func card() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }
}

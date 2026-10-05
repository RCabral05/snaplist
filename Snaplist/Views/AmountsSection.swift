import ArchiveCore
import SwiftUI

/// The dates and amounts read from a record: a receipt's or bill's total, or
/// a statement's lines. Everything here is a reading, so everything can be
/// corrected, and anything read from the page can be shown on the page.
struct AmountsSection: View {
    @Environment(AppModel.self) private var model

    let record: Record
    let transactions: [Amount]
    /// Jumps the page viewer to where an amount was printed.
    var showOnPage: (Amount) -> Void

    @State private var editing: Amount?
    @State private var items: [LineItem] = []
    @State private var thingDraft: Thing?
    @State private var isEditingDate = false
    @State private var isShowingAllLines = false

    var body: some View {
        Group {
            switch record.kind {
            case .receipt, .bill: totalCard
            case .statement: statementCard
            case .warranty, .manual, .identity, .document, .item, .other: EmptyView()
            }
        }
        .task(id: "\(record.id)-\(record.kind)-\(transactions.count)-\(model.amountsRevision)") {
            items = record.kind == .receipt ? model.items(of: record.id) : []
        }
        .sheet(item: $thingDraft) { thing in
            ThingEditor(thing: thing, sourceRecord: record.id)
        }
        .sheet(item: $editing) { transaction in
            AmountEditor(transaction: transaction, isNew: transaction.id == nil)
        }
        .sheet(isPresented: $isEditingDate) {
            DocumentDateEditor(record: record)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Receipts and bills

    private var total: Amount? { transactions.first }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.kind == .bill ? "Bill" : "Purchase")
                .font(Theme.display(.title3))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                row("Total") {
                    if let total {
                        Button {
                            editing = total
                        } label: {
                            Text(total.money.formatted)
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Button("Add Total") {
                            editing = Amount(recordId: record.id, date: record.documentDate, merchant: record.title,
                                                  amountCents: 0, kind: record.kind == .bill ? .bill : .purchase,
                                                  source: .person)
                        }
                    }
                }
                Divider().padding(.leading)
                row("Date") {
                    Button {
                        isEditingDate = true
                    } label: {
                        Text(record.documentDate.map { $0.date().formatted(date: .abbreviated, time: .omitted) } ?? "Add Date")
                    }
                }
                if let total {
                    Divider().padding(.leading)
                    row("From") { Text(total.merchant) }
                    Divider().padding(.leading)
                    row("Spending") { Text(total.category.label) }
                }
            }
            .font(.subheadline)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))

            if !items.isEmpty {
                itemsCard
            }

            HStack {
                Label(total == nil ? "No total was found on this one. Add it to count it in answers."
                                   : "Read automatically. Tap a value to correct it.",
                      systemImage: "text.viewfinder")
                Spacer()
                if let total, total.pagePosition != nil {
                    Button("Show on Page") { showOnPage(total) }
                        .fontWeight(.semibold)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal)
    }

    /// What the receipt lists, line by line, as read.
    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(items.count) \(items.count == 1 ? "item" : "items") · tap + to keep track of one as a Thing")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading) }
                    HStack {
                        Text(item.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(item.money.formatted).font(.subheadline).monospacedDigit()
                        // Something worth keeping track of: a TV, not eggs.
                        Button {
                            guard Pro.shared.require(.things) else { return }
                            thingDraft = model.draftThing(from: record.id, item: item)
                        } label: {
                            Image(systemName: "plus.circle").foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Make \(item.name) a Thing")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 9)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }

    // MARK: Statements

    private var statementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Transactions")
                    .font(Theme.display(.title3))
                Text("\(transactions.count)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add", systemImage: "plus") {
                    editing = Amount(recordId: record.id, date: record.documentDate, merchant: "",
                                          amountCents: 0, kind: .purchase, source: .person)
                }
                .labelStyle(.iconOnly)
            }
            .padding(.horizontal, 4)

            if transactions.isEmpty {
                Text("No transactions were found. Lines that start with a date and end with an amount are read; add any that were missed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            } else {
                summary
                VStack(spacing: 0) {
                    ForEach(Array(visibleLines.enumerated()), id: \.element.id) { index, transaction in
                        if index > 0 { Divider().padding(.leading) }
                        AmountRow(transaction: transaction)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = transaction }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = transaction }
                                if transaction.pagePosition != nil {
                                    Button("Show on Page", systemImage: "doc.text.magnifyingglass") { showOnPage(transaction) }
                                }
                            }
                    }
                    if transactions.count > visibleLines.count || isShowingAllLines {
                        Divider()
                        Button(isShowingAllLines ? "Show Fewer" : "Show All \(transactions.count)") {
                            withAnimation(.snappy) { isShowingAllLines.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 12)
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))

                Label("Read automatically. Tap a line to correct it; hold it to see it on the page.",
                      systemImage: "text.viewfinder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal)
    }

    private var visibleLines: [Amount] {
        isShowingAllLines ? transactions : Array(transactions.prefix(8))
    }

    /// Exact sums of the stored lines, by what they were.
    private var summary: some View {
        let currency = transactions.first?.currency ?? "USD"
        func sum(_ kinds: Set<AmountKind>) -> Money {
            Money(cents: transactions.filter { kinds.contains($0.kind) && $0.currency == currency }.reduce(0) { $0 + $1.amountCents },
                  currency: currency)
        }
        let purchases = sum([.purchase, .fee, .bill])
        let refunds = sum([.refund])
        let payments = sum([.payment])
        return HStack(spacing: 10) {
            stat("Purchases", purchases)
            if refunds.cents > 0 { stat("Refunds", refunds) }
            if payments.cents > 0 { stat("Payments", payments) }
        }
    }

    private func stat(_ title: String, _ money: Money) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(money.formatted).font(.headline).monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            value()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

/// A statement line: date, who, how much.
struct AmountRow: View {
    let transaction: Amount

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant.isEmpty ? transaction.memo : transaction.merchant)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let date = transaction.date {
                        Text(date.date(), format: .dateTime.month(.abbreviated).day())
                    }
                    if transaction.kind != .purchase {
                        Text("· \(transaction.kind.label)")
                    }
                    if transaction.isEdited {
                        Text("· edited")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(amountText)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(transaction.kind == .refund ? AnyShapeStyle(Color.green)
                                 : transaction.kind == .payment ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var amountText: String {
        let text = transaction.money.formatted
        return transaction.kind == .refund || transaction.kind == .payment ? "−\(text)" : text
    }
}

/// Correct an amount, or add one that wasn't found.
struct AmountEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State var transaction: Amount
    let isNew: Bool

    @State private var amountText: String
    @State private var hasDate: Bool
    @State private var date: Date
    /// Asking whether a new category is for this line or the merchant's.
    @State private var isAskingCategoryScope = false
    private let originalCategory: SpendCategory

    init(transaction: Amount, isNew: Bool) {
        _transaction = State(initialValue: transaction)
        self.isNew = isNew
        _amountText = State(initialValue: transaction.amountCents == 0 ? "" : Self.text(for: transaction.amountCents))
        _hasDate = State(initialValue: transaction.date != nil)
        _date = State(initialValue: transaction.date?.date() ?? .now)
        originalCategory = transaction.category
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Picker("Type", selection: $transaction.kind) {
                        ForEach(AmountKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    TextField("Merchant", text: $transaction.merchant)
                    Picker("Spending", selection: $transaction.category) {
                        ForEach(SpendCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("Date", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }
                    if !transaction.memo.isEmpty {
                        LabeledContent("Printed as") {
                            Text(transaction.memo).font(.footnote.monospaced()).multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("Details")
                } footer: {
                    Text("Spending decides which questions count it: “gas” counts Fuel, “eating out” counts Eating out.")
                }
                .listRowBackground(Theme.surface)

                if !isNew, let id = transaction.id {
                    Section {
                        Button("Delete This Amount", role: .destructive) {
                            model.deleteTransaction(id, of: transaction.recordId)
                            dismiss()
                        }
                    } footer: {
                        Text("Removes it from totals and answers. The original isn't changed.")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .warmForm()
            .navigationTitle(isNew ? "Add Amount" : "Correct Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if transaction.category != originalCategory, !merchant.isEmpty, otherLines > 0 {
                            isAskingCategoryScope = true
                        } else {
                            save(forMerchant: false)
                        }
                    }
                    .disabled(Self.cents(from: amountText) == nil)
                }
            }
            .confirmationDialog("Use \(transaction.category.label) for \(merchant)?", isPresented: $isAskingCategoryScope,
                                titleVisibility: .visible) {
                Button("All \(otherLines + 1) from \(merchant)") { save(forMerchant: true) }
                Button("Just This One") { save(forMerchant: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(otherLines) other \(otherLines == 1 ? "amount is" : "amounts are") from \(merchant). Choosing all also files future ones there.")
            }
        }
    }

    private var merchant: String {
        transaction.merchant.trimmingCharacters(in: .whitespaces)
    }

    /// Other saved amounts with the same merchant.
    private var otherLines: Int {
        max(0, model.lineCount(merchant: merchant) - (isNew ? 0 : 1))
    }

    private func save(forMerchant: Bool) {
        guard let cents = Self.cents(from: amountText) else { return }
        var updated = transaction
        updated.amountCents = cents
        updated.date = hasDate ? Day(date) : nil
        if forMerchant {
            // The rule sets this line too, without pinning it to one category.
            updated.category = originalCategory
            model.save(updated)
            model.setCategory(transaction.category, forMerchant: merchant)
        } else {
            model.save(updated)
        }
        dismiss()
    }

    static func text(for cents: Int64) -> String {
        String(format: "%lld.%02lld", cents / 100, cents % 100)
    }

    /// "39.82", "39,82", "$1,234.5", "40" → cents. Integer arithmetic only.
    static func cents(from text: String) -> Int64? {
        let cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !cleaned.isEmpty else { return nil }
        // The last separator with one or two digits after it is the decimal point.
        if let index = cleaned.lastIndex(where: { $0 == "." || $0 == "," }),
           cleaned.distance(from: index, to: cleaned.endIndex) - 1 <= 2 {
            let whole = cleaned[..<index].filter(\.isNumber)
            var fraction = String(cleaned[cleaned.index(after: index)...])
            while fraction.count < 2 { fraction += "0" }
            guard let units = Int64(whole.isEmpty ? "0" : String(whole)), let hundredths = Int64(fraction) else { return nil }
            return Self.cents(units: units, plus: hundredths)
        }
        guard let units = Int64(cleaned.filter(\.isNumber)) else { return nil }
        return Self.cents(units: units, plus: 0)
    }

    /// Nil for a number too big to be money, rather than a crash.
    private static func cents(units: Int64, plus hundredths: Int64) -> Int64? {
        let (scaled, overflowed) = units.multipliedReportingOverflow(by: 100)
        guard !overflowed, scaled <= 100_000_000_000_00 else { return nil }
        return scaled + hundredths
    }
}

/// The date a record is about, set by hand.
struct DocumentDateEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let record: Record
    @State private var date: Date

    init(record: Record) {
        self.record = record
        _date = State(initialValue: record.effectiveDay.date())
    }

    var body: some View {
        NavigationStack {
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.background)
                .navigationTitle(record.kind == .statement ? "Closing Date" : "Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            model.setDocumentDate(Day(date), for: record.id)
                            dismiss()
                        }
                    }
                }
        }
    }
}

extension Money {
    /// "$39.82", in the person's locale.
    var formatted: String {
        (Decimal(cents) / 100).formatted(.currency(code: currency))
    }
}

extension AmountKind {
    var label: String {
        switch self {
        case .purchase: "Purchase"
        case .bill: "Bill"
        case .fee: "Fee"
        case .refund: "Refund"
        case .payment: "Payment"
        }
    }
}

extension SpendCategory {
    var label: String {
        switch self {
        case .fuel: "Fuel"
        case .groceries: "Groceries"
        case .dining: "Eating out"
        case .pharmacy: "Pharmacy"
        case .utilities: "Utilities"
        case .subscriptions: "Subscriptions"
        case .shopping: "Shopping"
        case .travel: "Travel"
        case .other: "Other"
        }
    }
}

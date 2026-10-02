import ArchiveCore
import SwiftUI

// MARK: Budgets

/// This month against each budget, as bars.
struct BudgetBars: View {
    let statuses: [BudgetStatus]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(statuses) { status in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(status.budget.category?.label ?? "All spending").font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Money(cents: status.spentCents, currency: status.currency).formattedWhole) of \(Money(cents: status.budget.limitCents, currency: status.currency).formattedWhole)")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.accent.opacity(0.14))
                            Capsule().fill(color(status))
                                .frame(width: geometry.size.width * min(1, max(0.02, status.fraction)))
                        }
                    }
                    .frame(height: 8)
                    Text(caption(status)).font(.caption).foregroundStyle(status.fraction >= 1 ? Color.red : Color.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func color(_ status: BudgetStatus) -> Color {
        if status.fraction >= 1 { return .red }
        if status.fraction >= 0.8 { return .orange }
        return status.budget.category?.tint ?? Theme.accent
    }

    private func caption(_ status: BudgetStatus) -> String {
        let remaining = Money(cents: abs(status.remainingCents), currency: status.currency).formattedWhole
        return status.remainingCents >= 0 ? "\(remaining) left" : "\(remaining) over"
    }
}

/// Monthly limits per category, typed in dollars.
struct BudgetEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var values: [String: String] = [:]

    private let targets: [SpendCategory?] = [nil] + SpendCategory.allCases.filter { $0 != .other }.map { Optional($0) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(targets, id: \.self) { category in
                        HStack {
                            Label(category?.label ?? "All spending", systemImage: category?.symbol ?? "sum")
                            Spacer()
                            TextField("No limit", text: binding(category))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                        }
                    }
                } footer: {
                    Text("Monthly limits. Spending is counted the same way as everywhere else in Snaplist. With reminders on, you'll get a notification at 80% and at 100%.")
                }
                .listRowBackground(Theme.surface)
            }
            .warmForm()
            .navigationTitle("Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        for category in targets {
                            let text = values[key(category)] ?? ""
                            model.setBudget(text.isEmpty ? nil : AmountEditor.cents(from: text), for: category)
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                for status in model.budgetStatus() {
                    values[key(status.budget.category)] = AmountEditor.text(for: status.budget.limitCents)
                }
            }
        }
    }

    private func key(_ category: SpendCategory?) -> String { category?.rawValue ?? "all" }

    private func binding(_ category: SpendCategory?) -> Binding<String> {
        Binding(get: { values[key(category)] ?? "" }, set: { values[key(category)] = $0 })
    }
}

// MARK: Home inventory

/// Everything in the home inventory, by room, with its total value.
struct InventoryView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [Belonging] = []
    @State private var export: ReportExport = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if items.isEmpty {
                    ContentUnavailableView("Nothing in your inventory yet", systemImage: "sofa",
                                           description: Text("Open a photo, receipt or warranty of something you own and choose Add to Home Inventory. Useful for insurance claims."))
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(items.count) \(items.count == 1 ? "item" : "items")").font(.subheadline).foregroundStyle(.secondary)
                        Text(total).font(Theme.display(.largeTitle, weight: .bold)).monospacedDigit()
                    }
                    ForEach(rooms, id: \.self) { room in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(room).font(Theme.display(.title3))
                            VStack(spacing: 0) {
                                ForEach(Array(items(in: room).enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Divider().padding(.leading, 70) }
                                    NavigationLink(value: RecordListView.Destination(record: item.record)) {
                                        HStack(spacing: 12) {
                                            RecordThumbnail(record: item.record, pagePosition: nil, style: .square(44))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                                if !item.serialNumber.isEmpty {
                                                    Text("S/N \(item.serialNumber)").font(.caption).foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                            if let value = item.valueCents {
                                                Text(Money(cents: value, currency: item.currency).formatted)
                                                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
                        }
                    }
                    ReportExportButton(title: "Export for Insurance", state: $export) { try await model.exportInventory() }
                    Text("A zip with a PDF list, a spreadsheet, and every photo and receipt.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Home Inventory")
        .task(id: model.derivedRevision) { items = model.belongings() }
    }

    private var rooms: [String] {
        var seen = Set<String>()
        return items.map { $0.room.isEmpty ? "Unassigned" : $0.room }.filter { seen.insert($0).inserted }
    }

    private func items(in room: String) -> [Belonging] {
        items.filter { ($0.room.isEmpty ? "Unassigned" : $0.room) == room }
    }

    private var total: String {
        Money(cents: items.reduce(0) { $0 + ($1.valueCents ?? 0) }, currency: items.first?.currency ?? "USD").formatted
    }
}

/// On a record: its place in the inventory, or a way to add it.
struct BelongingSection: View {
    @Environment(AppModel.self) private var model
    let record: Record

    @State private var belonging: Belonging?
    @State private var editing: Belonging?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Home inventory").font(Theme.display(.title3)).padding(.horizontal, 4)
            if let belonging {
                Button { editing = belonging } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sofa").foregroundStyle(Theme.accent).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(belonging.name).font(.subheadline.weight(.medium))
                            Text([belonging.room.isEmpty ? nil : belonging.room,
                                  belonging.serialNumber.isEmpty ? nil : "S/N \(belonging.serialNumber)"].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let value = belonging.valueCents {
                            Text(Money(cents: value, currency: belonging.currency).formatted).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    editing = model.suggestedBelonging(for: record.id)
                } label: {
                    Label("Add to Home Inventory", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.horizontal)
        .sheet(item: $editing) { item in
            BelongingEditor(belonging: item, isNew: belonging == nil)
        }
        .task(id: "\(record.id)-\(model.derivedRevision)") { belonging = model.belonging(record.id) }
    }
}

private struct BelongingEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State var belonging: Belonging
    let isNew: Bool
    @State private var value: String

    init(belonging: Belonging, isNew: Bool) {
        _belonging = State(initialValue: belonging)
        self.isNew = isNew
        _value = State(initialValue: belonging.valueCents.map(AmountEditor.text(for:)) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What it is, like Samsung TV", text: $belonging.name)
                    TextField("Value (optional)", text: $value).keyboardType(.decimalPad)
                    TextField("Room (optional)", text: $belonging.room)
                    TextField("Serial number (optional)", text: $belonging.serialNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    Text("For things you own, in case you ever need to make an insurance claim. Only the name is needed; the value and serial number are read from a receipt when they're printed on it.")
                }
                .listRowBackground(Theme.surface)
                if !isNew {
                    Section {
                        Button("Remove from Inventory", role: .destructive) {
                            model.removeBelonging(belonging.record.id)
                            dismiss()
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .warmForm()
            .navigationTitle(isNew ? "Add to Inventory" : "Inventory Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = belonging
                        saved.valueCents = value.isEmpty ? nil : AmountEditor.cents(from: value)
                        model.save(saved)
                        dismiss()
                    }
                    .disabled(belonging.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: Tax report

/// Records marked for taxes in a year, by purpose, with an export for an
/// accountant.
struct TaxReportView: View {
    @Environment(AppModel.self) private var model
    @State private var years: [Int] = []
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var report: TaxReport?
    @State private var export: ReportExport = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if years.count > 1 {
                    Picker("Year", selection: $year) {
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if let report, !report.groups.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tagged for taxes in \(String(year))").font(.subheadline).foregroundStyle(.secondary)
                        Text(Money(cents: report.totalCents, currency: report.currency).formatted)
                            .font(Theme.display(.largeTitle, weight: .bold)).monospacedDigit()
                    }
                    ForEach(report.groups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(group.purpose).font(Theme.display(.title3))
                                Spacer()
                                Text(Money(cents: group.totalCents, currency: report.currency).formatted)
                                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 { Divider().padding(.leading) }
                                    NavigationLink(value: RecordListView.Destination(record: entry.record)) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(entry.record.title).font(.subheadline).lineLimit(1)
                                                Text(entry.record.effectiveDay.date(), format: .dateTime.month(.abbreviated).day())
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(entry.amount?.formatted ?? "No total").font(.subheadline).monospacedDigit()
                                                .foregroundStyle(entry.amount == nil ? .secondary : .primary)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
                        }
                    }
                    ReportExportButton(title: "Export for Your Accountant", state: $export) {
                        try await model.exportTaxReport(year: year)
                    }
                    Text("A zip with a PDF summary, a spreadsheet, and every original sorted by purpose. Totals are each receipt's or bill's total; check them before filing.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Nothing marked for \(String(year))", systemImage: "building.columns",
                                           description: Text("Open a receipt or bill and tap + Tax to mark it Business, Medical, Charity or anything else."))
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Tax Report")
        .onChange(of: year) { load() }
        .task(id: model.derivedRevision) {
            years = model.taxYears()
            if let latest = years.first, !years.contains(year) { year = latest }
            load()
        }
    }

    private func load() {
        report = model.taxReport(year: year)
        export = .idle
    }
}

// MARK: Exporting

enum ReportExport {
    case idle, working
    case ready(URL)
    case failed(String)
}

/// Makes a report zip, then offers it to save or share.
struct ReportExportButton: View {
    let title: String
    @Binding var state: ReportExport
    var make: () async throws -> URL

    var body: some View {
        Group {
            switch state {
            case .idle, .failed:
                Button {
                    state = .working
                    Task {
                        do { state = .ready(try await make()) } catch { state = .failed(error.localizedDescription) }
                    }
                } label: {
                    Label(title, systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
            case .working:
                ProgressView("Preparing…").frame(maxWidth: .infinity, minHeight: 44)
            case .ready(let url):
                ShareLink(item: url) {
                    Label("Save or Share \(url.lastPathComponent)", systemImage: "doc.zipper")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
            }
        }
        if case .failed(let message) = state {
            Text("Couldn't export: \(message)").font(.footnote).foregroundStyle(.red)
        }
    }
}

// MARK: Important documents

/// Passports, licences, registrations, policies and leases, by when they
/// run out. Kept out of Spotlight; behind the app lock like everything else.
struct ImportantDocumentsView: View {
    @Environment(AppModel.self) private var model
    @State private var documents: [ImportantDocument] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if documents.isEmpty {
                    ContentUnavailableView("No IDs or policies yet", systemImage: "person.text.rectangle",
                                           description: Text("Scan a passport, driver's licence, car registration, insurance card or lease. Snaplist reads when it expires and reminds you two months before."))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                            if index > 0 { Divider().padding(.leading, 70) }
                            NavigationLink(value: RecordListView.Destination(record: document.record)) {
                                HStack(spacing: 12) {
                                    RecordThumbnail(record: document.record, pagePosition: nil, style: .square(44))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(document.record.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                        Text(status(document))
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(color(document))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
                    Label("Expiry dates are read from the document. If one is missing or wrong, the document may print it in an unusual way; open it to check.",
                          systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                    Label("Never shown in Spotlight.", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("IDs & Policies")
        .task(id: model.derivedRevision) { documents = model.importantDocuments() }
    }

    private func days(_ document: ImportantDocument) -> Int? {
        document.expires.map { Day(.now).days(to: $0) }
    }

    private func status(_ document: ImportantDocument) -> String {
        guard let expires = document.expires, let days = days(document) else { return "No expiry date found" }
        let date = expires.date().formatted(date: .abbreviated, time: .omitted)
        if days < 0 { return "Expired \(date)" }
        if days == 0 { return "Expires today" }
        if days <= 90 { return "Expires in \(days) days · \(date)" }
        return "Expires \(date)"
    }

    private func color(_ document: ImportantDocument) -> Color {
        guard let days = days(document) else { return .secondary }
        if days < 0 { return .red }
        if days <= 90 { return .orange }
        return .secondary
    }
}

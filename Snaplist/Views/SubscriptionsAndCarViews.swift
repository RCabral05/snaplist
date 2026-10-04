import ArchiveCore
import SwiftUI

// MARK: Subscriptions

/// Everything that repeats, what it costs a month and a year, when it
/// charges next, and free trials before they turn into charges.
struct SubscriptionsView: View {
    @Environment(AppModel.self) private var model
    @State private var subscriptions: [Subscription] = []
    @State private var isAddingTrial = false

    private var active: [Subscription] { subscriptions.filter { !$0.isCancelled || $0.chargedAfterCancel } }
    private var cancelled: [Subscription] { subscriptions.filter { $0.isCancelled && !$0.chargedAfterCancel } }
    private var currency: String { subscriptions.first?.currency ?? "USD" }

    var body: some View {
        List {
            if subscriptions.isEmpty {
                ContentUnavailableView("No subscriptions found yet", systemImage: "repeat",
                                       description: Text("Import a few months of statements and anything charged every month or year shows up here. Add a free trial yourself to be reminded before it charges."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    HStack {
                        total("A month", active.reduce(0) { $0 + $1.monthlyCents })
                        Divider()
                        total("A year", active.reduce(0) { $0 + $1.yearlyCents })
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Theme.surface)

                Section("Active") {
                    ForEach(active) { subscription in
                        NavigationLink {
                            SubscriptionDetail(subscription: subscription)
                        } label: {
                            SubscriptionRow(subscription: subscription)
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                if !cancelled.isEmpty {
                    Section("Cancelled") {
                        ForEach(cancelled) { subscription in
                            NavigationLink {
                                SubscriptionDetail(subscription: subscription)
                            } label: {
                                SubscriptionRow(subscription: subscription)
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Subscriptions")
        .toolbar {
            Button("Add Trial", systemImage: "plus") { isAddingTrial = true }
        }
        .sheet(isPresented: $isAddingTrial) { TrialEditor() }
        .task(id: model.derivedRevision) { subscriptions = model.subscriptions() }
    }

    private func total(_ title: String, _ cents: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money(cents: cents, currency: currency).formatted)
                .font(Theme.display(.title2, weight: .bold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SubscriptionRow: View {
    let subscription: Subscription

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: subscription.category.symbol)
                .foregroundStyle(subscription.category.tint)
                .frame(width: 32, height: 32)
                .background(subscription.category.tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(subscription.name).font(.subheadline.weight(.medium))
                    if subscription.remind { Image(systemName: "bell.fill").font(.caption2).foregroundStyle(.secondary) }
                }
                Text(detail).font(.caption)
                    .foregroundStyle(subscription.chargedAfterCancel ? Color.red : Color.secondary)
            }
            Spacer()
            if let price = subscription.priceCents {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money(cents: price, currency: subscription.currency).formatted).font(.subheadline).monospacedDigit()
                    Text(subscription.cadence == .monthly ? "a month" : "a year").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var detail: String {
        if subscription.chargedAfterCancel { return "Charged again after you cancelled" }
        if let cancelled = subscription.cancelledOn { return "Cancelled \(cancelled.date().formatted(.dateTime.month(.abbreviated).day()))" }
        guard let next = subscription.nextCharge else { return "" }
        let date = next.date().formatted(.dateTime.month(.abbreviated).day())
        if subscription.trialEnds == next { return "Trial ends \(date)" }
        let days = Day(.now).days(to: next)
        return days < 0 ? "Was due \(date)" : days == 0 ? "Charges today" : "Next \(date)"
    }
}

private struct SubscriptionDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let subscription: Subscription

    @State private var remind = false
    @State private var hasTrial = false
    @State private var trialEnds = Date.now
    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            Section {
                Toggle("Remind Me 2 Days Before", isOn: $remind)
                    .onChange(of: remind) { save() }
                Toggle("Free Trial", isOn: $hasTrial)
                    .onChange(of: hasTrial) { save() }
                if hasTrial {
                    DatePicker("Trial Ends", selection: $trialEnds, displayedComponents: .date)
                        .onChange(of: trialEnds) { save() }
                }
            } footer: {
                Text("Reminders need notifications on in Settings → Reminders.")
            }
            .listRowBackground(Theme.surface)

            Section {
                if subscription.isCancelled {
                    Button("Mark as Active") { setCancelled(nil) }
                } else {
                    Button("I Cancelled It") { setCancelled(Day(.now)) }
                }
                if subscription.charge == nil {
                    Button("Delete Trial", role: .destructive) { isConfirmingDelete = true }
                        .confirmationDialog("Delete \(subscription.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                model.deleteTrial(subscription.key)
                                dismiss()
                            }
                        }
                }
            } footer: {
                Text(subscription.isCancelled
                     ? "If it charges again, Snaplist shows it in red."
                     : "Snaplist stops expecting charges, and tells you if one turns up anyway.")
            }
            .listRowBackground(Theme.surface)

            if let charge = subscription.charge {
                Section("Charges") {
                    ForEach(charge.charges.reversed()) { item in
                        NavigationLink(value: RecordListView.Destination(record: item.record, pagePosition: item.transaction.pagePosition)) {
                            HStack {
                                Text(item.day.date(), format: .dateTime.month(.abbreviated).day().year())
                                Spacer()
                                Text(item.transaction.money.formatted).monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .warmForm()
        .navigationTitle(subscription.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            remind = subscription.remind
            hasTrial = subscription.trialEnds != nil
            trialEnds = subscription.trialEnds?.date() ?? .now.addingTimeInterval(7 * 86_400)
        }
    }

    private func save() {
        var updated = subscription
        updated.remind = remind
        updated.trialEnds = hasTrial ? Day(trialEnds) : nil
        model.save(updated)
    }

    private func setCancelled(_ day: Day?) {
        var updated = subscription
        updated.remind = remind
        updated.trialEnds = hasTrial ? Day(trialEnds) : nil
        updated.cancelledOn = day
        model.save(updated)
        dismiss()
    }
}

private struct TrialEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var price = ""
    @State private var yearly = false
    @State private var ends = Date.now.addingTimeInterval(7 * 86_400)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Disney+", text: $name)
                    TextField("Price after the trial", text: $price).keyboardType(.decimalPad)
                    Picker("Charged", selection: $yearly) {
                        Text("Monthly").tag(false)
                        Text("Yearly").tag(true)
                    }
                    DatePicker("Trial Ends", selection: $ends, displayedComponents: .date)
                } footer: {
                    Text("You'll get a reminder two days before it starts charging, with reminders on in Settings.")
                }
                .listRowBackground(Theme.surface)
            }
            .warmForm()
            .navigationTitle("Free Trial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.addTrial(name: name.trimmingCharacters(in: .whitespaces),
                                       priceCents: price.isEmpty ? nil : AmountEditor.cents(from: price),
                                       cadence: yearly ? .yearly : .monthly, ends: Day(ends))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: Car

/// The car's service history from its receipts, today's estimated mileage,
/// and when the next oil change is due.
struct CarView: View {
    @Environment(AppModel.self) private var model
    @State private var car: CarSummary?
    @AppStorage(CarSettings.milesKey) private var miles = 5000
    @AppStorage(CarSettings.monthsKey) private var months = 6
    @State private var isAdding = false

    var body: some View {
        List {
            if let car {
                Section {
                    if let due = car.nextOilChange {
                        let days = Day(.now).days(to: due)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Next oil change").font(.caption).foregroundStyle(.secondary)
                            Text(days < 0 ? "Overdue since \(due.date().formatted(date: .abbreviated, time: .omitted))"
                                 : days == 0 ? "Due today" : "In \(days) days · \(due.date().formatted(date: .abbreviated, time: .omitted))")
                                .font(Theme.display(.title3, weight: .bold))
                                .foregroundStyle(days < 0 ? Color.red : days <= 14 ? Color.orange : Color.primary)
                            if let target = car.nextOilChangeMiles {
                                Text("or at \(target.formatted()) miles, whichever comes first").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if let estimate = car.estimatedMileage(on: Day(.now)) {
                        LabeledContent("Mileage today, about", value: estimate.formatted())
                    }
                    if let rate = car.milesPerDay {
                        LabeledContent("You drive about", value: "\(Int((rate * 365).rounded()).formatted()) miles a year")
                    }
                } footer: {
                    Text("Worked out from the mileage printed on your service receipts. Add each one to keep it right.")
                }
                .listRowBackground(Theme.surface)

                Section("Oil change every") {
                    Picker("Miles", selection: $miles) {
                        ForEach([3000, 5000, 7500, 10000], id: \.self) { Text("\($0.formatted()) miles").tag($0) }
                    }
                    Picker("Or", selection: $months) {
                        ForEach([3, 6, 12], id: \.self) { Text("\($0) months").tag($0) }
                    }
                }
                .listRowBackground(Theme.surface)
                .onChange(of: miles) { model.refreshDerived() }
                .onChange(of: months) { model.refreshDerived() }

                Section("History") {
                    ForEach(car.services) { service in
                        NavigationLink(value: RecordListView.Destination(record: service.record)) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(service.kinds.map(\.label).joined(separator: ", ")).font(.subheadline.weight(.medium))
                                    Spacer()
                                    if let amount = service.amount {
                                        Text(amount.formatted).font(.subheadline).monospacedDigit()
                                    }
                                }
                                Text([service.day.date().formatted(date: .abbreviated, time: .omitted), service.record.title,
                                      service.mileage.map { "\($0.formatted()) mi" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            } else {
                ContentUnavailableView("No car service yet", systemImage: "car",
                                       description: Text("Scan an oil change or repair receipt, ideally one that prints the mileage, or tap + to add receipts you already have."))
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Car")
        .toolbar {
            Button("Add Receipts", systemImage: "plus") { isAdding = true }
        }
        .sheet(isPresented: $isAdding) {
            RecordPicker(title: "Add to Car", excluding: Set(car?.services.map(\.id) ?? [])) { ids in
                model.addToCar(ids)
            }
        }
        .task(id: model.derivedRevision) { car = model.carSummary() }
    }
}

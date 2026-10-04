import ArchiveCore
import SwiftUI

// MARK: Changes

/// "Verizon bill up $24 (17%)": one row.
struct PriceChangeRow: View {
    let change: PriceChange

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: change.deltaCents > 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(change.deltaCents > 0 ? Color.orange : Color.green)
                .frame(width: 32, height: 32)
                .background((change.deltaCents > 0 ? Color.orange : Color.green).opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(change.merchant) \(change.kind == .bill ? "bill" : "charge") \(change.deltaCents > 0 ? "up" : "down") \(delta)")
                    .font(.subheadline.weight(.medium)).lineLimit(1)
                Text("\(change.previous.transaction.money.formatted) → \(change.latest.transaction.money.formatted) · \(abs(change.percent))%")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var delta: String { Money(cents: abs(change.deltaCents), currency: change.currency).formatted }
}

/// What changed between two bills, or two charges of a subscription.
struct PriceChangeView: View {
    let change: PriceChange

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(change.kind == .bill ? "Compared with the bill before" : "Compared with the charge before")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("\(change.deltaCents > 0 ? "+" : "−")\(Money(cents: abs(change.deltaCents), currency: change.currency).formatted)")
                        .font(Theme.display(.largeTitle, weight: .bold)).monospacedDigit()
                        .foregroundStyle(change.deltaCents > 0 ? Color.orange : Color.green)
                    Text("\(abs(change.percent))% \(change.deltaCents > 0 ? "more" : "less") than last time")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    side("Before", change.previous)
                    Divider().padding(.leading)
                    side("Latest", change.latest)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))

                if !change.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What changed").font(Theme.display(.title3))
                        VStack(spacing: 0) {
                            ForEach(Array(change.lines.enumerated()), id: \.offset) { index, line in
                                if index > 0 { Divider().padding(.leading) }
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(line.name).font(.subheadline)
                                        Text(lineCaption(line)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                    Spacer()
                                    Text("\(line.delta > 0 ? "+" : "−")\(Money(cents: abs(line.delta), currency: change.currency).formatted)")
                                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                                        .foregroundStyle(line.delta > 0 ? Color.orange : Color.green)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                            }
                        }
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    }
                } else if change.kind == .bill {
                    Text("These bills don't list their charges in a way Snaplist could read, so only the totals are compared.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(change.merchant)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func side(_ title: String, _ item: Counted) -> some View {
        NavigationLink(value: RecordListView.Destination(record: item.record, pagePosition: item.transaction.pagePosition)) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(item.day.date().formatted(date: .abbreviated, time: .omitted)).font(.subheadline)
                }
                Spacer()
                Text(item.transaction.money.formatted).font(.subheadline.weight(.semibold)).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func lineCaption(_ line: PriceChange.Line) -> String {
        switch (line.before, line.after) {
        case (nil, let after?): "New: \(Money(cents: after, currency: change.currency).formatted)"
        case (let before?, nil): "Gone: was \(Money(cents: before, currency: change.currency).formatted)"
        case (let before?, let after?):
            "\(Money(cents: before, currency: change.currency).formatted) → \(Money(cents: after, currency: change.currency).formatted)"
        case (nil, nil): ""
        }
    }
}

// MARK: Collections

/// A collection's card on Home.
struct CollectionCard: View {
    let collection: Collection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: collection.symbol).font(.title3).foregroundStyle(Theme.accent)
            Text(collection.name).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .padding(14)
        .frame(width: 110, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }
}

/// One collection: what's been spent, and everything in it, newest first.
struct CollectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let collectionId: UUID

    @State private var collection: Collection?
    @State private var records: [Record] = []
    @State private var lines: [Counted] = []
    @State private var spending: SpendingAnswer?
    @State private var isEditing = false
    @State private var isAdding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if collection?.name == "Car" {
                    NavigationLink {
                        CarView()
                    } label: {
                        Label("Maintenance and next oil change", systemImage: "wrench.and.screwdriver")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    }
                    .buttonStyle(.plain)
                }
                if let spending, !spending.counted.isEmpty {
                    NavigationLink {
                        ScrollView {
                            AnswerView(result: .spending(spending), reask: { _ in }, decided: {})
                                .padding()
                        }
                        .background(Theme.background)
                        .navigationTitle("\(collection?.name ?? "") spending")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Spent, all time").font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                Text(spending.totals.map(\.formatted).joined(separator: " + "))
                                    .font(Theme.display(.largeTitle, weight: .bold)).monospacedDigit()
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            Text("\(spending.counted.count) amounts").font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if records.isEmpty && lines.isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: collection?.symbol ?? "folder",
                                           description: Text("Records that mention this collection's words show up here by themselves. You can also add any record from its ⋯ menu."))
                }

                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Records").font(Theme.display(.title3))
                        VStack(spacing: 0) {
                            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                if index > 0 { Divider().padding(.leading, 70) }
                                NavigationLink(value: RecordListView.Destination(record: record)) {
                                    HStack(spacing: 12) {
                                        RecordThumbnail(record: record, pagePosition: nil, style: .square(44))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(record.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                            Text("\(record.kind.label) · \(record.effectiveDay.date().formatted(date: .abbreviated, time: .omitted))")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if let total = model.totals[record.id] {
                                            Text(total.formatted).font(.subheadline).monospacedDigit()
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Leave Out of \(collection?.name ?? "This")", systemImage: "minus.circle", role: .destructive) {
                                        model.setRecord(record.id, in: collectionId, included: false)
                                    }
                                }
                            }
                        }
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    }
                }

                if !lines.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("On card statements").font(Theme.display(.title3))
                        VStack(spacing: 0) {
                            ForEach(Array(lines.prefix(30).enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().padding(.leading) }
                                NavigationLink(value: RecordListView.Destination(record: item.record, pagePosition: item.transaction.pagePosition)) {
                                    CountedRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    }
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(collection?.name ?? "Collection")
        .toolbar {
            Button("Add Records", systemImage: "plus") { isAdding = true }
            Button("Edit") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            if let collection { CollectionEditor(collection: collection, isNew: false) }
        }
        .sheet(isPresented: $isAdding) {
            RecordPicker(title: "Add to \(collection?.name ?? "Collection")", excluding: Set(records.map(\.id))) { ids in
                for id in ids { model.setRecord(id, in: collectionId, included: true) }
            }
        }
        .task(id: model.derivedRevision) { load() }
    }

    private func load() {
        guard let found = model.collections().first(where: { $0.id == collectionId }) else {
            collection = nil
            return
        }
        collection = found
        records = model.records(in: found)
        lines = model.statementLines(in: found)
        spending = model.spending(in: found)
    }
}

/// Make or change a collection: a name, an icon, and the words that pull
/// records in.
struct CollectionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var collection: Collection
    let isNew: Bool
    /// After saving: a record's page puts the record in the new collection.
    var onSave: ((Collection) -> Void)? = nil

    static let symbols = ["house", "car", "building.columns", "briefcase", "airplane", "figure.2.and.child.holdinghands",
                          "pawprint", "heart", "graduationcap", "wrench.and.screwdriver", "gift", "folder"]

    var body: some View {
        NavigationStack {
            Form {
                if isNew {
                    Section("Start from") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Collection.presets.filter { preset in !model.collections().contains { $0.name == preset.name } }) { preset in
                                    Button {
                                        collection.name = preset.name
                                        collection.symbol = preset.symbol
                                        collection.keywords = preset.keywords
                                    } label: {
                                        Label(preset.name, systemImage: preset.symbol)
                                            .font(.subheadline.weight(.medium))
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(Theme.accent.opacity(collection.name == preset.name ? 0.25 : 0.1), in: .capsule)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
                Section {
                    TextField("Name, like Car or Florida Trip", text: $collection.name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Self.symbols, id: \.self) { symbol in
                                Button { collection.symbol = symbol } label: {
                                    Image(systemName: symbol)
                                        .frame(width: 40, height: 40)
                                        .background(collection.symbol == symbol ? Theme.accent.opacity(0.25) : Color.clear, in: .circle)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(symbol)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.surface)
                Section {
                    TextField("Words, separated by commas", text: $collection.keywords, axis: .vertical)
                        .lineLimit(2...6)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Pull in records that mention")
                } footer: {
                    Text("Any record whose text or name has one of these words joins, and so do card statement lines that mention one. Add or leave out records by hand anytime.")
                }
                .listRowBackground(Theme.surface)
                if !isNew {
                    Section {
                        Button("Delete Collection", role: .destructive) {
                            model.deleteCollection(collection.id)
                            dismiss()
                        }
                    } footer: {
                        Text("Its records stay in your library.")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .warmForm()
            .navigationTitle(isNew ? "New Collection" : "Edit Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.save(collection)
                        onSave?(collection)
                        dismiss()
                    }
                    .disabled(collection.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// From a record's ⋯ menu: put it in a collection, or take it out.
/// On a record's page: the collections it's in, and a menu to add it to
/// others, take it out, or start a new one with it in.
struct RecordCollectionsMenu: View {
    @Environment(AppModel.self) private var model
    let record: Record

    @State private var memberOf: Set<UUID> = []
    @State private var isCreating = false

    var body: some View {
        let collections = model.collections()
        Menu {
            ForEach(collections) { collection in
                let isIn = memberOf.contains(collection.id)
                Button {
                    model.setRecord(record.id, in: collection.id, included: !isIn)
                    if isIn { memberOf.remove(collection.id) } else { memberOf.insert(collection.id) }
                } label: {
                    Label(collection.name, systemImage: isIn ? "checkmark" : collection.symbol)
                }
            }
            if !collections.isEmpty { Divider() }
            Button("New Collection…", systemImage: "plus") { isCreating = true }
        } label: {
            HStack(spacing: 4) {
                Text(label(collections)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
        }
        .sheet(isPresented: $isCreating) {
            CollectionEditor(collection: Collection(name: "", symbol: "folder", keywords: []), isNew: true) { created in
                model.setRecord(record.id, in: created.id, included: true)
                memberOf.insert(created.id)
            }
        }
        .task(id: "\(record.id)-\(model.derivedRevision)") {
            memberOf = Set(model.collections().filter { collection in
                model.records(in: collection).contains { $0.id == record.id }
            }.map(\.id))
        }
    }

    private func label(_ collections: [Collection]) -> String {
        let names = collections.filter { memberOf.contains($0.id) }.map(\.name)
        return names.isEmpty ? "Add" : names.joined(separator: ", ")
    }
}

import ArchiveCore
import SwiftUI

// MARK: All things

/// Everything owned, by room, with its total value, and a way to package
/// some of it for an insurance claim.
struct ThingsView: View {
    @Environment(AppModel.self) private var model
    @State private var profiles: [ThingProfile] = []
    @State private var export: ReportExport = .idle
    @State private var isSelecting = false
    @State private var selected = Set<UUID>()
    @State private var claim: ReportExport = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if profiles.isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: "sofa",
                                           description: Text("Open a receipt and tap + next to something you bought, or open any photo, warranty or manual and choose Make a Thing. Its receipt, warranty and manual stay together."))
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(profiles.count) \(profiles.count == 1 ? "thing" : "things")").font(.subheadline).foregroundStyle(.secondary)
                        Text(total).font(Theme.display(.largeTitle, weight: .bold)).monospacedDigit()
                    }
                    ForEach(rooms, id: \.self) { room in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(room).font(Theme.display(.title3))
                            VStack(spacing: 0) {
                                ForEach(Array(items(in: room).enumerated()), id: \.element.id) { index, profile in
                                    if index > 0 { Divider().padding(.leading, 70) }
                                    if isSelecting {
                                        Button { toggle(profile.id) } label: { row(profile, selectable: true) }
                                            .buttonStyle(.plain)
                                    } else {
                                        NavigationLink { ThingProfileView(thingId: profile.id) } label: { row(profile, selectable: false) }
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
                        }
                    }
                    if isSelecting {
                        ReportExportButton(title: "Make Claim Packet (\(selected.count))", state: $claim) {
                            try await model.exportInventory(selected: selected)
                        }
                        .disabled(selected.isEmpty)
                        Text("One zip for your insurer: a PDF list with values, serial numbers and dates, and every photo, receipt and warranty for the things you picked.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ReportExportButton(title: "Export Everything for Insurance", state: $export) { try await model.exportInventory() }
                        Text("A zip with a PDF list, a spreadsheet, and every photo, receipt and warranty.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Things")
        .toolbar {
            if !profiles.isEmpty {
                Button(isSelecting ? "Done" : "Claim Packet") {
                    isSelecting.toggle()
                    selected = []
                    claim = .idle
                }
            }
        }
        .task(id: model.derivedRevision) { profiles = model.thingProfiles() }
    }

    private func row(_ profile: ThingProfile, selectable: Bool) -> some View {
        HStack(spacing: 12) {
            if selectable {
                Image(systemName: selected.contains(profile.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected.contains(profile.id) ? Theme.accent : Color.secondary)
            }
            ThingThumbnail(profile: profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.thing.name).font(.subheadline.weight(.medium)).lineLimit(1)
                WarrantyLabel(profile: profile).font(.caption)
            }
            Spacer()
            if let value = profile.thing.value {
                Text(value.formatted).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        claim = .idle
    }

    private var rooms: [String] {
        var seen = Set<String>()
        return profiles.map { $0.thing.room.isEmpty ? "Unassigned" : $0.thing.room }.filter { seen.insert($0).inserted }
    }

    private func items(in room: String) -> [ThingProfile] {
        profiles.filter { ($0.thing.room.isEmpty ? "Unassigned" : $0.thing.room) == room }
    }

    private var total: String {
        Money(cents: profiles.reduce(0) { $0 + ($1.thing.valueCents ?? 0) }, currency: profiles.first?.thing.currency ?? "USD").formatted
    }
}

/// A thing's picture: its photo if it has one, else its receipt.
struct ThingThumbnail: View {
    let profile: ThingProfile
    var size: CGFloat = 44

    var body: some View {
        if let record = (profile.links(.photo) + profile.links).first?.record {
            RecordThumbnail(record: record, pagePosition: nil, style: .square(size))
        } else {
            Image(systemName: "shippingbox")
                .frame(width: size, height: size)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Theme.accent)
        }
    }
}

/// "Under warranty until Mar 2028" in green, "Warranty ended" in orange.
struct WarrantyLabel: View {
    let profile: ThingProfile

    var body: some View {
        switch profile.warranty(on: Day(.now)) {
        case .covered(let until):
            Label("Warranty to \(until.date().formatted(.dateTime.month(.abbreviated).year()))", systemImage: "checkmark.shield")
                .foregroundStyle(.green)
        case .ended(let on):
            Label("Warranty ended \(on.date().formatted(.dateTime.month(.abbreviated).year()))", systemImage: "exclamationmark.shield")
                .foregroundStyle(.orange)
        case .unknown:
            Text(profile.thing.purchased.map { "Bought \($0.date().formatted(date: .abbreviated, time: .omitted))" } ?? "No warranty date")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: One thing

/// Everything about one thing: what it cost, where and when, its warranty,
/// serial number, and its receipt, warranty, manual and photos together.
struct ThingProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let thingId: UUID

    @State private var profile: ThingProfile?
    @State private var suggestions: [Record] = []
    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            if let profile {
                VStack(alignment: .leading, spacing: 22) {
                    header(profile)
                    details(profile)
                    documents(profile)
                    if !suggestions.isEmpty {
                        suggestionsSection
                    }
                    Button("Delete This Thing", role: .destructive) { isConfirmingDelete = true }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                    Text("Deleting the thing keeps its receipt, warranty and other records.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                .padding()
            }
        }
        .background(Theme.background)
        .navigationTitle(profile?.thing.name ?? "Thing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            if let profile { ThingEditor(thing: profile.thing, sourceRecord: nil) }
        }
        .confirmationDialog("Delete \(profile?.thing.name ?? "this")?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.deleteThing(thingId)
                dismiss()
            }
        }
        .task(id: model.derivedRevision) {
            profile = model.thingProfile(thingId)
            suggestions = model.suggestedLinks(for: thingId)
        }
    }

    private func header(_ profile: ThingProfile) -> some View {
        HStack(spacing: 14) {
            ThingThumbnail(profile: profile, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.thing.name).font(Theme.display(.title2, weight: .bold))
                if let value = profile.thing.value {
                    Text(value.formatted).font(.title3.weight(.semibold)).monospacedDigit()
                }
                WarrantyLabel(profile: profile).font(.subheadline)
            }
        }
    }

    private func details(_ profile: ThingProfile) -> some View {
        let thing = profile.thing
        let rows: [(String, String)] = [
            ("Bought", thing.purchased.map { $0.date().formatted(date: .long, time: .omitted) } ?? "—"),
            ("From", thing.store.isEmpty ? "—" : thing.store),
            ("Warranty", profile.warrantyEnds.map { $0.date().formatted(date: .long, time: .omitted) } ?? "Not known"),
            ("Serial number", thing.serialNumber.isEmpty ? "—" : thing.serialNumber),
            ("Room", thing.room.isEmpty ? "—" : thing.room),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().padding(.leading) }
                HStack {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1).multilineTextAlignment(.trailing).textSelection(.enabled)
                }
                .font(.subheadline)
                .padding(.horizontal)
                .padding(.vertical, 11)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }

    private func documents(_ profile: ThingProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Documents").font(Theme.display(.title3))
            if profile.links.isEmpty {
                Text("No documents linked. Open a receipt, warranty, manual or photo and choose Add to a Thing.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(profile.links.enumerated()), id: \.element.id) { index, link in
                        if index > 0 { Divider().padding(.leading, 70) }
                        NavigationLink(value: RecordListView.Destination(record: link.record)) {
                            HStack(spacing: 12) {
                                RecordThumbnail(record: link.record, pagePosition: nil, style: .square(44))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(link.role.label).font(.caption.weight(.semibold)).foregroundStyle(link.record.kind.tint)
                                    Text(link.record.title).font(.subheadline).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Unlink", systemImage: "link.badge.plus", role: .destructive) {
                                model.unlink(link.record.id, from: thingId)
                            }
                        }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
            }
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Might be about this").font(Theme.display(.title3))
            ForEach(suggestions.prefix(5)) { record in
                HStack(spacing: 12) {
                    RecordThumbnail(record: record, pagePosition: nil, style: .square(40))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.title).font(.subheadline).lineLimit(1)
                        Text(record.kind.label).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Link") { model.link(record.id, to: thingId) }
                        .buttonStyle(.glass)
                        .font(.subheadline.weight(.semibold))
                }
            }
            Text("They mention its model or serial number, or its name.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension ThingRole {
    var label: String {
        switch self {
        case .receipt: "Receipt"
        case .warranty: "Warranty"
        case .manual: "Manual"
        case .photo: "Photo"
        case .statement: "Card statement"
        case .other: "Document"
        }
    }
}

// MARK: Editing

/// Make or change a thing. Only the name is needed.
struct ThingEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State var thing: Thing
    /// Set when making a new thing from a record, which it's linked to.
    let sourceRecord: UUID?
    @State private var value: String
    @State private var hasPurchased: Bool
    @State private var purchased: Date
    @State private var hasWarranty: Bool
    @State private var warranty: Date

    init(thing: Thing, sourceRecord: UUID?) {
        _thing = State(initialValue: thing)
        self.sourceRecord = sourceRecord
        _value = State(initialValue: thing.valueCents.map(AmountEditor.text(for:)) ?? "")
        _hasPurchased = State(initialValue: thing.purchased != nil)
        _purchased = State(initialValue: thing.purchased?.date() ?? .now)
        _hasWarranty = State(initialValue: thing.warrantyEnds != nil)
        _warranty = State(initialValue: thing.warrantyEnds?.date() ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What it is, like LG TV", text: $thing.name)
                    TextField("Price (optional)", text: $value).keyboardType(.decimalPad)
                    TextField("Store (optional)", text: $thing.store)
                    Toggle("Purchase date", isOn: $hasPurchased.animation())
                    if hasPurchased { DatePicker("Bought", selection: $purchased, displayedComponents: .date) }
                } footer: {
                    Text("Filled in from the receipt where possible.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Toggle("Warranty end", isOn: $hasWarranty.animation())
                    if hasWarranty { DatePicker("Ends", selection: $warranty, displayedComponents: .date) }
                    TextField("Serial number (optional)", text: $thing.serialNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Room (optional)", text: $thing.room)
                } footer: {
                    Text("Leave the warranty off if a warranty document is linked: its date is read from it.")
                }
                .listRowBackground(Theme.surface)
            }
            .warmForm()
            .navigationTitle(sourceRecord == nil ? "Edit Thing" : "New Thing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = thing
                        saved.name = thing.name.trimmingCharacters(in: .whitespaces)
                        saved.valueCents = value.isEmpty ? nil : AmountEditor.cents(from: value)
                        saved.purchased = hasPurchased ? Day(purchased) : nil
                        saved.warrantyEnds = hasWarranty ? Day(warranty) : nil
                        model.save(saved, from: sourceRecord)
                        dismiss()
                    }
                    .disabled(thing.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: On a record

/// On a record: the things it's about, and ways to make or join one.
struct ThingsSection: View {
    @Environment(AppModel.self) private var model
    let record: Record

    @State private var linked: [Thing] = []
    @State private var draft: Thing?
    @State private var isPicking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Things").font(Theme.display(.title3)).padding(.horizontal, 4)
            ForEach(linked) { thing in
                NavigationLink { ThingProfileView(thingId: thing.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox").foregroundStyle(Theme.accent).frame(width: 28)
                        Text(thing.name).font(.subheadline.weight(.medium))
                        Spacer()
                        if let value = thing.value { Text(value.formatted).font(.subheadline).monospacedDigit() }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                Button {
                    draft = model.draftThing(from: record.id)
                } label: {
                    Label("Make a Thing", systemImage: "plus.circle").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                Button {
                    isPicking = true
                } label: {
                    Label("Add to a Thing", systemImage: "link").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
            }
            .font(.subheadline.weight(.semibold))
            if linked.isEmpty {
                Text("For something you own: keeps its receipt, warranty, manual and photos together, and answers “is my TV still under warranty?”")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
        }
        .padding(.horizontal)
        .sheet(item: $draft) { thing in
            ThingEditor(thing: thing, sourceRecord: record.id)
        }
        .sheet(isPresented: $isPicking) {
            ThingPicker(recordId: record.id)
                .presentationDetents([.medium, .large])
        }
        .task(id: "\(record.id)-\(model.derivedRevision)") { linked = model.things(linkedTo: record.id) }
    }
}

/// Choose an existing thing to link a record to.
private struct ThingPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recordId: UUID

    var body: some View {
        NavigationStack {
            List {
                let profiles = model.thingProfiles()
                if profiles.isEmpty {
                    Text("No things yet. Use Make a Thing instead.").foregroundStyle(.secondary)
                }
                ForEach(profiles) { profile in
                    Button {
                        model.link(recordId, to: profile.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ThingThumbnail(profile: profile, size: 36)
                            Text(profile.thing.name).foregroundStyle(.primary)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .warmForm()
            .navigationTitle("Add to a Thing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

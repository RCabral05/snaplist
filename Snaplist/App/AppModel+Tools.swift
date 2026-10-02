import ArchiveCore
import Foundation

/// Budgets, the home inventory and the tax report, for their screens.
extension AppModel {
    // MARK: Budgets

    /// This calendar month, which budgets are measured against.
    var budgetMonth: DayRange {
        let today = Day(.now)
        return DayRange.month(today.month, of: today.year) ?? DayRange(today, today)
    }

    func budgetStatus() -> [BudgetStatus] { derived.budgets }

    func setBudget(_ cents: Int64?, for category: SpendCategory?) {
        do {
            try archive.store.setBudget(cents, for: category)
            amountsChanged()
        } catch {
            errorMessage = "Couldn't save the budget: \(error.localizedDescription)"
        }
    }

    /// A notification the first time a budget passes 80% and 100% in a
    /// month, when reminders are on.
    func checkBudgets() {
        guard Reminders.isEnabled else { return }
        let month = budgetMonth.start
        for status in budgetStatus() {
            for threshold in [100, 80] where status.fraction * 100 >= Double(threshold) {
                let key = "budgetAlert-\(status.id)-\(month.year)-\(month.month)-\(threshold)"
                guard !UserDefaults.standard.bool(forKey: key) else { break }
                UserDefaults.standard.set(true, forKey: key)
                Task { await Reminders.notifyBudget(status, threshold: threshold) }
                break
            }
        }
    }

    // MARK: Things

    func thingProfiles() -> [ThingProfile] {
        (try? archive.store.thingProfiles()) ?? []
    }

    func thingProfile(_ id: UUID) -> ThingProfile? {
        try? archive.store.thingProfile(id)
    }

    func things(linkedTo recordId: UUID) -> [Thing] {
        (try? archive.store.things(linkedTo: recordId)) ?? []
    }

    func draftThing(from recordId: UUID, item: LineItem? = nil) -> Thing? {
        try? archive.store.draftThing(from: recordId, item: item)
    }

    func suggestedLinks(for thingId: UUID) -> [Record] {
        (try? archive.store.suggestedLinks(for: thingId)) ?? []
    }

    /// Saves a thing; a new one is linked to the record it came from.
    func save(_ thing: Thing, from recordId: UUID? = nil) {
        do {
            if let recordId {
                try archive.store.createThing(thing, from: recordId)
            } else {
                try archive.store.save(thing)
            }
            amountsChanged()
        } catch {
            errorMessage = "Couldn't save that: \(error.localizedDescription)"
        }
    }

    func deleteThing(_ id: UUID) {
        do {
            try archive.store.delete(thing: id)
            amountsChanged()
        } catch {
            errorMessage = "Couldn't delete that: \(error.localizedDescription)"
        }
    }

    func link(_ recordId: UUID, to thingId: UUID) {
        do {
            try archive.store.link(recordId, to: thingId)
            amountsChanged()
        } catch {
            errorMessage = "Couldn't link that: \(error.localizedDescription)"
        }
    }

    func unlink(_ recordId: UUID, from thingId: UUID) {
        do {
            try archive.store.unlink(recordId, from: thingId)
            amountsChanged()
        } catch {
            errorMessage = "Couldn't unlink that: \(error.localizedDescription)"
        }
    }

    func inventorySummary() -> InventorySummary? { derived.inventory }

    func importantDocuments() -> [ImportantDocument] { derived.importantDocuments }

    /// A zip for an insurer: a PDF list, a spreadsheet, and every photo,
    /// receipt and warranty. Only `selected` things for a claim packet.
    func exportInventory(selected: Set<UUID>? = nil) async throws -> URL {
        let profiles = thingProfiles().filter { selected?.contains($0.id) ?? true }
        let isClaim = selected != nil
        let summary = ReportPDF.Document(
            title: isClaim ? "Claim Packet" : "Home Inventory",
            subtitle: "\(profiles.count) \(profiles.count == 1 ? "item" : "items"), made with Snaplist on \(Date.now.formatted(date: .long, time: .omitted))",
            sections: Dictionary(grouping: profiles, by: { $0.thing.room.isEmpty ? "Unassigned" : $0.thing.room })
                .sorted { $0.key < $1.key }
                .map { room, items in
                    ReportPDF.Section(heading: room, rows: items.map { profile in
                        let item = profile.thing
                        return ReportPDF.Row(
                            left: item.name,
                            detail: [item.serialNumber.isEmpty ? nil : "S/N \(item.serialNumber)",
                                     item.purchased.map { "Bought \($0.date().formatted(date: .abbreviated, time: .omitted))" + (item.store.isEmpty ? "" : " at \(item.store)") },
                                     profile.warrantyEnds.map { "Warranty to \($0.date().formatted(date: .abbreviated, time: .omitted))" },
                                     profile.links.isEmpty ? nil : "\(profile.links.count) documents"]
                                .compactMap { $0 }.joined(separator: " · "),
                            right: item.value?.formatted ?? "")
                    }, total: Money(cents: items.reduce(0) { $0 + ($1.thing.valueCents ?? 0) }, currency: items.first?.thing.currency ?? "USD").formatted)
                },
            grandTotal: Money(cents: profiles.reduce(0) { $0 + ($1.thing.valueCents ?? 0) },
                              currency: profiles.first?.thing.currency ?? "USD").formatted)
        let folderName = isClaim ? "Snaplist Claim Packet" : "Snaplist Home Inventory"
        return try await Self.writeReport(archive, pdf: summary, pdfName: isClaim ? "Claim.pdf" : "Inventory.pdf") { archive, parent in
            try ArchiveExporter.exportInventory(archive, into: parent, selected: selected, name: folderName)
        }
    }

    // MARK: Changes and prices

    func priceChanges() -> [PriceChange] { derived.priceChanges }

    // MARK: Collections

    func collections() -> [Collection] { derived.collections }

    func records(in collection: Collection) -> [Record] {
        (try? archive.store.records(in: collection)) ?? []
    }

    func statementLines(in collection: Collection) -> [Counted] {
        (try? archive.store.statementLines(in: collection)) ?? []
    }

    func save(_ collection: Collection) {
        do {
            try archive.store.save(collection)
            refreshDerived()
        } catch {
            errorMessage = "Couldn't save the collection: \(error.localizedDescription)"
        }
    }

    func deleteCollection(_ id: UUID) {
        do {
            try archive.store.delete(collection: id)
            refreshDerived()
        } catch {
            errorMessage = "Couldn't delete the collection: \(error.localizedDescription)"
        }
    }

    func setRecord(_ recordId: UUID, in collectionId: UUID, included: Bool?) {
        do {
            try archive.store.setRecord(recordId, in: collectionId, included: included)
            refreshDerived()
        } catch {
            errorMessage = "Couldn't change the collection: \(error.localizedDescription)"
        }
    }

    /// Everything a collection's records and lines add up to.
    func spending(in collection: Collection) -> SpendingAnswer? {
        try? archive.store.answer(SpendingQuery().within(collection, records: records(in: collection)))
    }

    // MARK: Tax report

    func taxYears() -> [Int] { derived.taxYears }

    func taxReport(year: Int) -> TaxReport? {
        try? archive.store.taxReport(year: year)
    }

    /// A zip of the year's tax-tagged records: a PDF summary, a spreadsheet,
    /// and the originals by purpose.
    func exportTaxReport(year: Int) async throws -> URL {
        guard let report = taxReport(year: year) else { throw CocoaError(.fileNoSuchFile) }
        let summary = ReportPDF.Document(
            title: "Tax Report \(year)",
            subtitle: "Records tagged for taxes, made with Snaplist on \(Date.now.formatted(date: .long, time: .omitted))",
            sections: report.groups.map { group in
                ReportPDF.Section(heading: group.purpose, rows: group.entries.map { entry in
                    ReportPDF.Row(left: entry.record.title,
                                  detail: "\(entry.record.kind.label) · \(entry.record.effectiveDay.date().formatted(date: .abbreviated, time: .omitted))",
                                  right: entry.amount?.formatted ?? "—")
                }, total: Money(cents: group.totalCents, currency: report.currency).formatted)
            },
            grandTotal: Money(cents: report.totalCents, currency: report.currency).formatted)
        return try await Self.writeReport(archive, pdf: summary, pdfName: "Summary.pdf") { archive, parent in
            try ArchiveExporter.exportTaxReport(archive, year: year, into: parent)
        }
    }

    /// Writes a report folder, adds its PDF, and zips it, off the main actor.
    @concurrent
    private static func writeReport(_ archive: Archive, pdf: ReportPDF.Document, pdfName: String,
                                    write: @Sendable (Archive, URL) throws -> URL) async throws -> URL {
        // One folder per kind of report, so exporting one doesn't delete the other's zip.
        let parent = FileManager.default.temporaryDirectory.appending(path: "Reports", directoryHint: .isDirectory)
            .appending(path: (pdfName as NSString).deletingPathExtension, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: parent)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let folder = try write(archive, parent)
        try ReportPDF.render(pdf).write(to: folder.appending(path: pdfName))
        defer { try? FileManager.default.removeItem(at: folder) }
        return try zip(folder)
    }
}

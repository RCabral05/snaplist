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

    // MARK: Home inventory

    func belongings() -> [Belonging] {
        (try? archive.store.belongings()) ?? []
    }

    func belonging(_ recordId: UUID) -> Belonging? {
        try? archive.store.belonging(recordId)
    }

    func suggestedBelonging(for recordId: UUID) -> Belonging? {
        try? archive.store.suggestedBelonging(for: recordId)
    }

    func save(_ belonging: Belonging) {
        do {
            try archive.store.save(belonging)
            amountsChanged()
        } catch {
            errorMessage = "Couldn't save that: \(error.localizedDescription)"
        }
    }

    func removeBelonging(_ recordId: UUID) {
        do {
            try archive.store.removeBelonging(recordId)
            amountsChanged()
        } catch {
            errorMessage = "Couldn't remove that: \(error.localizedDescription)"
        }
    }

    func inventorySummary() -> InventorySummary? { derived.inventory }

    func importantDocuments() -> [ImportantDocument] { derived.importantDocuments }

    /// A zip of the inventory's spreadsheet, a PDF summary, and every photo
    /// and receipt.
    func exportInventory() async throws -> URL {
        let summary = ReportPDF.Document(
            title: "Home Inventory",
            subtitle: "Made with Snaplist on \(Date.now.formatted(date: .long, time: .omitted))",
            sections: Dictionary(grouping: belongings(), by: { $0.room.isEmpty ? "Unassigned" : $0.room })
                .sorted { $0.key < $1.key }
                .map { room, items in
                    ReportPDF.Section(heading: room, rows: items.map { item in
                        ReportPDF.Row(left: item.name,
                                      detail: [item.serialNumber.isEmpty ? nil : "S/N \(item.serialNumber)",
                                               item.purchased.map { "Bought \($0.date().formatted(date: .abbreviated, time: .omitted))" }]
                                        .compactMap { $0 }.joined(separator: " · "),
                                      right: item.valueCents.map { Money(cents: $0, currency: item.currency).formatted } ?? "")
                    }, total: Money(cents: items.reduce(0) { $0 + ($1.valueCents ?? 0) }, currency: items.first?.currency ?? "USD").formatted)
                },
            grandTotal: inventorySummary().map { Money(cents: $0.totalCents, currency: $0.currency).formatted })
        return try await Self.writeReport(archive, pdf: summary, pdfName: "Inventory.pdf") { archive, parent in
            try ArchiveExporter.exportInventory(archive, into: parent)
        }
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

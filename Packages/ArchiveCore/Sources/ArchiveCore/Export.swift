import Foundation
import GRDB

/// Everything in the archive as ordinary files a person can open anywhere:
///
///     Snaplist Export 2026-10-01/
///       Read Me.txt
///       Records.csv          one row per record
///       Amounts.csv          every total and statement line
///       Receipts/2026-09-28 Shell.jpg
///       Receipts/2026-09-28 Shell.txt     the text read from it
///       Statements/…
///
/// Nothing is left out and nothing needs Snaplist to read.
public enum ArchiveExporter {
    public struct Summary: Equatable, Sendable {
        public var records: Int
        public var files: Int
        public var amounts: Int
    }

    /// Writes the export into a new folder inside `parent` and returns it.
    @discardableResult
    public static func export(_ archive: Archive, into parent: URL, today: Day = Day(Date())) throws -> (URL, Summary) {
        let folder = parent.appendingPathComponent("Snaplist Export \(today.iso)", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let records = try archive.store.records()
        var recordRows = [["Name", "Category", "Date", "Added", "People and places", "Files", "Status"]]
        let tagsByRecord = try archive.store.tagsByRecord()
        var amountRows = [["Date", "Merchant", "Amount", "Currency", "Type", "Spending category", "Record",
                           "Printed as", "Corrected by you"]]
        var usedNames = Set<String>()
        var fileCount = 0
        var amountCount = 0

        for record in records {
            let kindFolder = folder.appendingPathComponent(folderName(for: record.kind), isDirectory: true)
            try fm.createDirectory(at: kindFolder, withIntermediateDirectories: true)
            let base = uniqueName("\(record.effectiveDay.iso) \(safeFileName(record.title))", in: kindFolder.lastPathComponent,
                                  used: &usedNames)

            let assets = try archive.store.assets(of: record.id)
            var written: [String] = []
            for (index, asset) in assets.enumerated() {
                let ext = (asset.fileName as NSString).pathExtension
                let name = (assets.count > 1 ? "\(base) (\(index + 1))" : base) + (ext.isEmpty ? "" : ".\(ext)")
                let source = archive.url(for: asset)
                guard fm.fileExists(atPath: source.path) else { continue }
                try fm.copyItem(at: source, to: kindFolder.appendingPathComponent(name))
                written.append("\(kindFolder.lastPathComponent)/\(name)")
                fileCount += 1
            }

            let text = try archive.store.pages(of: record.id).map(\.text).joined(separator: "\n\n— next page —\n\n")
            if !text.isEmpty {
                try Data(text.utf8).write(to: kindFolder.appendingPathComponent("\(base).txt"))
            }

            recordRows.append([record.title, record.kind.rawValue.capitalized, record.documentDate?.iso ?? "",
                               Day(record.createdAt).iso, (tagsByRecord[record.id] ?? []).map(\.name).joined(separator: "; "),
                               written.joined(separator: "; "), record.status.rawValue])

            for amount in try archive.store.transactions(of: record.id) {
                amountRows.append([amount.date?.iso ?? record.documentDate?.iso ?? "", amount.merchant,
                                   decimal(amount.amountCents), amount.currency, amount.kind.rawValue.capitalized,
                                   amount.category.rawValue.capitalized, record.title, amount.memo,
                                   amount.isEdited ? "Yes" : "No"])
                amountCount += 1
            }
        }

        try csv(recordRows).write(to: folder.appendingPathComponent("Records.csv"))
        try csv(amountRows).write(to: folder.appendingPathComponent("Amounts.csv"))
        let readMe = """
            Your Snaplist archive, exported \(today.iso).

            Each folder holds one category. Every original is here exactly as you saved it, named by its date and name. \
            Next to it, a .txt file holds the text Snaplist read from it.

            Records.csv lists every record. Amounts.csv lists every total and statement line that was read or typed in; \
            amounts are always positive, and Type says whether money went out (Purchase, Bill, Fee) or came back (Refund, Payment).
            """
        try Data(readMe.utf8).write(to: folder.appendingPathComponent("Read Me.txt"))
        return (folder, Summary(records: records.count, files: fileCount, amounts: amountCount))
    }

    static func folderName(for kind: RecordKind) -> String {
        switch kind {
        case .receipt: "Receipts"
        case .statement: "Statements"
        case .bill: "Bills"
        case .warranty: "Warranties"
        case .manual: "Manuals"
        case .identity: "IDs and Policies"
        case .document: "Documents"
        case .item: "Notes"
        case .other: "Other"
        }
    }

    /// No slashes, colons or control characters; short enough for any disk.
    static func safeFileName(_ name: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters).union(.newlines)
        let cleaned = name.unicodeScalars.map { banned.contains($0) ? "-" : String($0) }.joined()
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(80))
    }

    private static func uniqueName(_ name: String, in folder: String, used: inout Set<String>) -> String {
        var candidate = name
        var counter = 2
        while !used.insert("\(folder)/\(candidate)".lowercased()).inserted {
            candidate = "\(name) \(counter)"
            counter += 1
        }
        return candidate
    }

    static func decimal(_ cents: Int64) -> String {
        "\(cents / 100).\(String(format: "%02lld", cents % 100))"
    }

    /// RFC 4180, with a byte-order mark so spreadsheet apps read it as UTF-8.
    static func csv(_ rows: [[String]]) -> Data {
        let text = rows.map { row in
            row.map { field in
                field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline })
                    ? "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\"" : field
            }.joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
        return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }
}

// MARK: Tax report

/// Records tagged for taxes in one year, grouped by purpose, with totals.
public struct TaxReport: Sendable {
    public struct Entry: Hashable, Identifiable, Sendable {
        public var record: Record
        /// The receipt's or bill's total; nil for records without one.
        public var amount: Money?
        public var id: UUID { record.id }
    }

    public struct Group: Hashable, Identifiable, Sendable {
        public var purpose: String
        public var entries: [Entry]
        public var totalCents: Int64 { entries.reduce(0) { $0 + ($1.amount?.cents ?? 0) } }
        public var id: String { purpose }
    }

    public var year: Int
    public var groups: [Group]
    public var currency: String

    public var totalCents: Int64 { groups.reduce(0) { $0 + $1.totalCents } }
}

/// The home inventory's total, for its header.
public struct InventorySummary: Sendable {
    public var count: Int
    public var totalCents: Int64
    public var currency: String
}

extension ArchiveStore {
    /// Every record dated in `year` with a tax tag, grouped by the tag.
    public func taxReport(year: Int) throws -> TaxReport {
        guard let range = DayRange.year(year) else { return TaxReport(year: year, groups: [], currency: "USD") }
        let tagsByRecord = try tagsByRecord()
        let totals = try recordTotals()
        var groups: [String: [TaxReport.Entry]] = [:]
        for record in try records() where range.contains(record.effectiveDay) {
            for tag in tagsByRecord[record.id] ?? [] where tag.kind == .tax {
                groups[tag.name, default: []].append(TaxReport.Entry(record: record, amount: totals[record.id]))
            }
        }
        let currency = totals.values.first?.currency ?? "USD"
        return TaxReport(
            year: year,
            groups: groups.map { TaxReport.Group(purpose: $0.key, entries: $0.value.sorted { $0.record.effectiveDay < $1.record.effectiveDay }) }
                .sorted { $0.purpose.localizedCaseInsensitiveCompare($1.purpose) == .orderedAscending },
            currency: currency)
    }

    /// Years that have any tax-tagged record, newest first.
    public func taxYears() throws -> [Int] {
        let tagged = try tagsByRecord().filter { $0.value.contains { $0.kind == .tax } }.keys
        return Set(try records().filter { tagged.contains($0.id) }.map(\.effectiveDay.year)).sorted(by: >)
    }

    public func inventorySummary() throws -> InventorySummary {
        try thingsSummary()
    }
}

extension ArchiveExporter {
    /// A year's tax-tagged records for an accountant: `Summary.csv` and each
    /// original in a folder per purpose. Returns the folder.
    public static func exportTaxReport(_ archive: Archive, year: Int, into parent: URL) throws -> URL {
        let report = try archive.store.taxReport(year: year)
        let folder = parent.appendingPathComponent("Snaplist Tax Report \(year)", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        var rows = [["Purpose", "Date", "Name", "Category", "Amount", "Currency", "Files"]]
        var used = Set<String>()
        for group in report.groups {
            let groupFolder = folder.appendingPathComponent(safeFileName(group.purpose), isDirectory: true)
            try fm.createDirectory(at: groupFolder, withIntermediateDirectories: true)
            for entry in group.entries {
                let files = try copyOriginals(of: entry.record, archive: archive, to: groupFolder, used: &used)
                rows.append([group.purpose, entry.record.effectiveDay.iso, entry.record.title, entry.record.kind.rawValue.capitalized,
                             entry.amount.map { decimal($0.cents) } ?? "", entry.amount?.currency ?? "",
                             files.map { "\(groupFolder.lastPathComponent)/\($0)" }.joined(separator: "; ")])
            }
            rows.append([group.purpose, "", "Total", "", decimal(group.totalCents), report.currency, ""])
        }
        try csv(rows).write(to: folder.appendingPathComponent("Summary.csv"))
        return folder
    }

    /// The home inventory for an insurer: `Inventory.csv` and each thing's
    /// photos, receipts and warranties. Only `selected` things when given
    /// (a claim packet). Returns the folder.
    public static func exportInventory(_ archive: Archive, into parent: URL, selected: Set<UUID>? = nil,
                                       name: String = "Snaplist Home Inventory") throws -> URL {
        let profiles = try archive.store.thingProfiles().filter { selected?.contains($0.id) ?? true }
        let folder = parent.appendingPathComponent(name, isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        let files = folder.appendingPathComponent("Photos and Receipts", isDirectory: true)
        try fm.createDirectory(at: files, withIntermediateDirectories: true)

        var rows = [["Item", "Room", "Value", "Currency", "Serial number", "Bought", "Store", "Warranty ends", "Files"]]
        var used = Set<String>()
        for profile in profiles {
            let item = profile.thing
            var copied: [String] = []
            for link in profile.links {
                copied += try copyOriginals(of: link.record, archive: archive, to: files, used: &used,
                                            name: "\(item.name) \(link.role.rawValue)")
            }
            rows.append([item.name, item.room, item.valueCents.map(decimal) ?? "", item.currency, item.serialNumber,
                         item.purchased?.iso ?? "", item.store, profile.warrantyEnds?.iso ?? "",
                         copied.map { "\(files.lastPathComponent)/\($0)" }.joined(separator: "; ")])
        }
        let total = profiles.reduce(Int64(0)) { $0 + ($1.thing.valueCents ?? 0) }
        rows.append(["Total", "", decimal(total), profiles.first?.thing.currency ?? "USD", "", "", "", "", ""])
        try csv(rows).write(to: folder.appendingPathComponent("Inventory.csv"))
        return folder
    }

    /// Copies a record's originals into `folder` as "date name (n).ext";
    /// returns the file names.
    static func copyOriginals(of record: Record, archive: Archive, to folder: URL, used: inout Set<String>,
                              name: String? = nil) throws -> [String] {
        let assets = try archive.store.assets(of: record.id)
        var base = "\(record.effectiveDay.iso) \(safeFileName(name ?? record.title))"
        var counter = 2
        while used.contains(base.lowercased()) { base = "\(record.effectiveDay.iso) \(safeFileName(name ?? record.title)) \(counter)"; counter += 1 }
        used.insert(base.lowercased())
        var names: [String] = []
        for (index, asset) in assets.enumerated() {
            let source = archive.url(for: asset)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let ext = (asset.fileName as NSString).pathExtension
            let fileName = (assets.count > 1 ? "\(base) (\(index + 1))" : base) + (ext.isEmpty ? "" : ".\(ext)")
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(fileName))
            names.append(fileName)
        }
        return names
    }
}

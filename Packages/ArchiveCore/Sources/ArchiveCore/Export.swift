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
        var recordRows = [["Name", "Category", "Date", "Added", "Files", "Status"]]
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
                               Day(record.createdAt).iso, written.joined(separator: "; "), record.status.rawValue])

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

import Foundation
import GRDB

/// A space like Home, Car or Taxes. Records come in on their own when their
/// text or name mentions one of its words; any record can also be added or
/// left out by hand, and that choice wins.
public struct Collection: Codable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public var id: UUID
    public var name: String
    /// An SF Symbol name.
    public var symbol: String
    /// Comma-separated: "car, oil change, tires".
    public var keywords: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, symbol: String, keywords: [String], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.keywords = keywords.joined(separator: ", ")
        self.createdAt = createdAt
    }

    public var keywordList: [String] {
        keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    /// Ready-made starting points.
    public static let presets: [Collection] = [
        Collection(name: "Home", symbol: "house", keywords: [
            "home depot", "lowe's", "lowes", "ikea", "mortgage", "rent", "landlord", "plumber", "plumbing",
            "electrician", "hvac", "furnace", "roofing", "appliance", "furniture", "homeowners", "renters insurance",
            "property tax", "hoa", "pg&e", "national grid", "eversource", "water bill"]),
        Collection(name: "Car", symbol: "car", keywords: [
            "car", "auto", "vehicle", "registration", "dmv", "oil change", "jiffy lube", "valvoline", "tire", "tires",
            "brakes", "mechanic", "auto repair", "car wash", "firestone", "midas", "pep boys", "autozone",
            "geico", "progressive", "state farm", "allstate", "inspection", "parking", "toll", "e-zpass"]),
        Collection(name: "Taxes", symbol: "building.columns", keywords: [
            "w-2", "w2", "1099", "1098", "irs", "tax return", "property tax", "donation", "charity"]),
        Collection(name: "Work", symbol: "briefcase", keywords: [
            "invoice", "reimbursement", "expense report", "staples", "office depot", "client"]),
        Collection(name: "Travel", symbol: "airplane", keywords: [
            "airline", "airlines", "flight", "boarding pass", "hotel", "airbnb", "marriott", "hilton", "hyatt",
            "jetblue", "american airlines", "southwest airlines", "rental car", "hertz", "avis", "itinerary"]),
        Collection(name: "Kids", symbol: "figure.2.and.child.holdinghands", keywords: [
            "school", "daycare", "tuition", "pediatric", "pediatrician", "summer camp", "babysitter", "toys"]),
        Collection(name: "Pet", symbol: "pawprint", keywords: [
            "vet", "veterinary", "animal hospital", "petco", "petsmart", "chewy", "grooming", "kennel"]),
    ]
}

extension ArchiveStore {
    public func collections() throws -> [Collection] {
        try db.read { try Collection.order(Column("createdAt")).fetchAll($0) }
    }

    public func save(_ collection: Collection) throws {
        try db.write { try collection.save($0) }
    }

    public func delete(collection id: UUID) throws {
        try db.write { _ = try Collection.deleteOne($0, key: id) }
    }

    /// Puts a record in a collection (true), keeps it out (false), or goes
    /// back to the keywords deciding (nil).
    public func setRecord(_ recordId: UUID, in collectionId: UUID, included: Bool?) throws {
        try db.write { db in
            if let included {
                try db.execute(sql: """
                    INSERT INTO collectionRecord (collectionId, recordId, included) VALUES (?, ?, ?)
                    ON CONFLICT(collectionId, recordId) DO UPDATE SET included = excluded.included
                    """, arguments: [collectionId, recordId, included])
            } else {
                try db.execute(sql: "DELETE FROM collectionRecord WHERE collectionId = ? AND recordId = ?",
                               arguments: [collectionId, recordId])
            }
        }
    }

    /// The records in a collection, newest first: those its words find, plus
    /// those added by hand, minus those left out. Words match whole ("car"
    /// isn't "card"). Statements aren't pulled in whole by one line; their
    /// matching lines count toward the collection's spending instead.
    public func records(in collection: Collection) throws -> [Record] {
        var ids = Set<UUID>()
        for keyword in collection.keywordList {
            let phrase = "\"" + keyword.replacingOccurrences(of: "\"", with: "") + "\""
            let found = try db.read { db in
                try UUID.fetchAll(db, sql: """
                    SELECT DISTINCT page.recordId FROM searchIndex JOIN page ON page.id = searchIndex.rowid
                    JOIN record ON record.id = page.recordId
                    WHERE searchIndex MATCH ? AND record.kind != 'statement'
                    """, arguments: [phrase])
            }
            ids.formUnion(found)
        }
        let manual = try db.read { db in
            try Row.fetchAll(db, sql: "SELECT recordId, included FROM collectionRecord WHERE collectionId = ?",
                             arguments: [collection.id])
        }
        for row in manual {
            let id: UUID = row["recordId"]
            if row["included"] as Bool { ids.insert(id) } else { ids.remove(id) }
        }
        return try db.read { try Record.fetchAll($0, keys: Array(ids)) }
            .sorted { ($0.effectiveDay, $0.createdAt) > ($1.effectiveDay, $1.createdAt) }
    }

    /// Statement lines that belong to a collection by what they say.
    public func statementLines(in collection: Collection) throws -> [Counted] {
        let words = collection.keywordList
        guard !words.isEmpty else { return [] }
        return try spendingAmounts().filter { item in
            item.transaction.source == .statement && words.contains { Self.containsWord(item.haystack, $0) }
        }
        .sorted { ($0.day, $0.id) > ($1.day, $1.id) }
    }

    /// The collection a question names: "my car", "the house" for Home,
    /// "trip" for Travel, or a collection's own name.
    public func collection(namedIn question: String) throws -> Collection? {
        let text = " " + question.lowercased().components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined(separator: " ") + " "
        let aliases: [String: [String]] = ["home": ["house", "home"], "car": ["car", "vehicle"],
                                           "travel": ["travel", "trip", "trips", "vacation"], "pet": ["pet", "dog", "cat"],
                                           "kids": ["kids", "children"], "work": ["work"]]
        return try collections().first { collection in
            let name = collection.name.lowercased()
            return (aliases[name] ?? [name]).contains { text.contains(" \($0) ") }
        }
    }
}

extension SpendingQuery {
    /// The same question narrowed to a collection: its records, and
    /// statement lines that mention its words.
    public func within(_ collection: Collection, records: [Record]) -> SpendingQuery {
        var query = self
        query.onlyRecords = Set(records.map(\.id))
        query.lineKeywords = collection.keywordList
        query.scopeLabel = collection.name
        return query
    }
}

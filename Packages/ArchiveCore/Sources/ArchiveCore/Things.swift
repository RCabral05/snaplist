import Foundation
import GRDB

/// Something owned, with everything about it in one place: what it cost,
/// where and when it was bought, its serial number, its warranty, and the
/// records that show it (receipt, warranty, manual, photos, the card line).
public struct Thing: Codable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public var id: UUID
    public var name: String
    public var valueCents: Int64?
    public var currency: String
    public var store: String
    public var purchased: Day?
    public var serialNumber: String
    public var room: String
    /// Typed in by the person; otherwise read from a linked warranty.
    public var warrantyEnds: Day?
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, valueCents: Int64? = nil, currency: String = "USD", store: String = "",
                purchased: Day? = nil, serialNumber: String = "", room: String = "", warrantyEnds: Day? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.valueCents = valueCents
        self.currency = currency
        self.store = store
        self.purchased = purchased
        self.serialNumber = serialNumber
        self.room = room
        self.warrantyEnds = warrantyEnds
        self.createdAt = createdAt
    }

    public var value: Money? { valueCents.map { Money(cents: $0, currency: currency) } }
}

/// How a record relates to a thing.
public enum ThingRole: String, Codable, CaseIterable, Sendable {
    case receipt, warranty, manual, photo, statement, other

    static func of(_ kind: RecordKind) -> ThingRole {
        switch kind {
        case .receipt, .bill: .receipt
        case .warranty: .warranty
        case .manual: .manual
        case .statement: .statement
        case .item, .other: .photo
        case .identity, .document: .other
        }
    }
}

public struct ThingLink: Hashable, Identifiable, Sendable {
    public var record: Record
    public var role: ThingRole
    public var id: UUID { record.id }
}

/// Where a thing's warranty stands today.
public enum WarrantyStatus: Hashable, Sendable {
    case covered(until: Day)
    case ended(on: Day)
    case unknown
}

/// A thing with its links and warranty worked out.
public struct ThingProfile: Hashable, Identifiable, Sendable {
    public var thing: Thing
    public var links: [ThingLink]
    /// The warranty's end: typed in, else read from a linked warranty.
    public var warrantyEnds: Day?
    /// The printed line the warranty date came from, when read.
    public var warrantyEvidence: String?

    public var id: UUID { thing.id }

    public func warranty(on today: Day) -> WarrantyStatus {
        guard let end = warrantyEnds else { return .unknown }
        return end >= today ? .covered(until: end) : .ended(on: end)
    }

    public func links(_ role: ThingRole) -> [ThingLink] { links.filter { $0.role == role } }
}

extension ArchiveStore {
    // MARK: Reading

    public func things() throws -> [Thing] {
        try db.read { try Thing.order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll($0) }
    }

    public func thingProfiles() throws -> [ThingProfile] {
        try things().compactMap { try thingProfile($0.id) }
    }

    public func thingProfile(_ id: UUID) throws -> ThingProfile? {
        try db.read { db in
            guard let thing = try Thing.fetchOne(db, key: id) else { return nil }
            let rows = try Row.fetchAll(db, sql: "SELECT recordId, role FROM thingRecord WHERE thingId = ?", arguments: [id])
            let records = try Record.fetchAll(db, keys: rows.map { $0["recordId"] as UUID })
            let byId = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            let links = rows.compactMap { row -> ThingLink? in
                guard let record = byId[row["recordId"]] else { return nil }
                return ThingLink(record: record, role: ThingRole(rawValue: row["role"]) ?? .other)
            }
            .sorted { ($0.role.order, $0.record.effectiveDay) < ($1.role.order, $1.record.effectiveDay) }

            var ends = thing.warrantyEnds
            var evidence: String?
            if ends == nil {
                for link in links where link.role == .warranty {
                    let rows = Extractor.rows(of: try Self.storedPages(of: link.record.id, in: db))
                    if let found = Self.expiry(in: rows, record: link.record) {
                        ends = found.day
                        evidence = found.evidence
                        break
                    }
                }
            }
            return ThingProfile(thing: thing, links: links, warrantyEnds: ends, warrantyEvidence: evidence)
        }
    }

    /// The things a record belongs to.
    public func things(linkedTo recordId: UUID) throws -> [Thing] {
        try db.read { db in
            try Thing.fetchAll(db, sql: """
                SELECT thing.* FROM thing JOIN thingRecord ON thingRecord.thingId = thing.id
                WHERE thingRecord.recordId = ? ORDER BY thing.name
                """, arguments: [recordId])
        }
    }

    // MARK: Writing

    public func save(_ thing: Thing) throws {
        try db.write { try thing.save($0) }
    }

    public func delete(thing id: UUID) throws {
        try db.write { _ = try Thing.deleteOne($0, key: id) }
    }

    public func link(_ recordId: UUID, to thingId: UUID, as role: ThingRole? = nil) throws {
        try db.write { db in
            guard let record = try Record.fetchOne(db, key: recordId) else { return }
            try db.execute(sql: """
                INSERT INTO thingRecord (thingId, recordId, role) VALUES (?, ?, ?)
                ON CONFLICT(thingId, recordId) DO UPDATE SET role = excluded.role
                """, arguments: [thingId, recordId, (role ?? ThingRole.of(record.kind)).rawValue])
        }
    }

    public func unlink(_ recordId: UUID, from thingId: UUID) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM thingRecord WHERE thingId = ? AND recordId = ?", arguments: [thingId, recordId])
        }
    }

    /// A first draft of a thing from a record, or from one line of a
    /// receipt: its name, price, store, date and printed serial number.
    public func draftThing(from recordId: UUID, item: LineItem? = nil) throws -> Thing? {
        guard let record = try record(recordId) else { return nil }
        let total = try transactions(of: recordId).first { $0.source == .receipt || $0.source == .bill }
        let serial = try db.read { db in
            Self.serialNumber(in: Extractor.rows(of: try Self.storedPages(of: recordId, in: db)))
        }
        if let item {
            return Thing(name: item.name, valueCents: item.amountCents, currency: item.currency,
                         store: total?.merchant ?? record.title, purchased: total?.date ?? record.documentDate,
                         serialNumber: serial ?? "")
        }
        return Thing(name: record.kind == .receipt ? "" : record.title, valueCents: total?.amountCents,
                     currency: total?.currency ?? "USD", store: total?.merchant ?? "", purchased: record.documentDate,
                     serialNumber: serial ?? "")
    }

    /// Creates a thing linked to the record it came from.
    @discardableResult
    public func createThing(_ thing: Thing, from recordId: UUID) throws -> Thing {
        try save(thing)
        try link(recordId, to: thing.id)
        return thing
    }

    // MARK: Suggestions

    /// Records that look like they're about this thing but aren't linked:
    /// they print its serial number or model number, or share its name's
    /// distinctive words. Best first.
    public func suggestedLinks(for thingId: UUID) throws -> [Record] {
        guard let profile = try thingProfile(thingId) else { return [] }
        let linked = Set(profile.links.map(\.record.id))
        var scored: [UUID: Int] = [:]
        // Serial and model numbers: a word with letters and digits, 5+ long.
        let codes = ([profile.thing.serialNumber] + profile.thing.name.split(separator: " ").map(String.init))
            .filter { $0.count >= 5 && $0.contains(where: \.isNumber) && $0.contains(where: \.isLetter) }
        for code in codes {
            for hit in try search(code, limit: 20) { scored[hit.id, default: 0] += 10 }
        }
        let words = profile.thing.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).filter { $0.count >= 3 && !QuestionParser.filler.contains($0) }
        if words.count >= 2, let hits = try? search(words.joined(separator: " "), limit: 20) {
            for hit in hits { scored[hit.id, default: 0] += 3 }
        }
        let records = try db.read { try Record.fetchAll($0, keys: Array(scored.keys)) }
        return records.filter { !linked.contains($0.id) }.sorted { (scored[$0.id] ?? 0) > (scored[$1.id] ?? 0) }
    }

    // MARK: Summary

    public func thingsSummary() throws -> InventorySummary {
        let all = try things()
        let currency = all.first?.currency ?? "USD"
        return InventorySummary(count: all.count,
                                totalCents: all.filter { $0.currency == currency }.reduce(0) { $0 + ($1.valueCents ?? 0) },
                                currency: currency)
    }
}

extension ThingRole {
    var order: Int {
        switch self {
        case .receipt: 0
        case .warranty: 1
        case .manual: 2
        case .photo: 3
        case .statement: 4
        case .other: 5
        }
    }
}

// MARK: Questions about things

/// "When did I buy my TV?", "Is my TV still under warranty?", "Show me the
/// receipt for my TV", "What do I own that's out of warranty?"
public struct ThingAnswer: Sendable {
    public enum Topic: Sendable, Equatable {
        case bought, warranty, documents, value, overview
    }

    public var profiles: [ThingProfile]
    public var topic: Topic
    /// For "out of warranty" questions: every thing whose warranty ended.
    public var isOutOfWarrantyList: Bool
}

extension ArchiveStore {
    /// When a question names a saved thing (or asks which are out of
    /// warranty), the thing and what's being asked about it. Nil otherwise.
    public func thingQuestion(_ question: String, today: Day) throws -> ThingAnswer? {
        let text = " " + question.lowercased().replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'s ", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator: " ") + " "
        let profiles = try thingProfiles()
        guard !profiles.isEmpty else { return nil }

        if ["out of warranty", "no longer under warranty", "not under warranty", "warranty expired", "warranties expired",
            "warranty ended", "expired warrant"].contains(where: { text.contains($0) }) {
            let ended = profiles.filter { if case .ended = $0.warranty(on: today) { true } else { false } }
            return ThingAnswer(profiles: ended, topic: .warranty, isOutOfWarrantyList: true)
        }

        // The thing whose name shares the most words with the question.
        let scored = profiles.map { profile -> (ThingProfile, Int) in
            let words = profile.thing.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init).filter { $0.count >= 2 && !QuestionParser.filler.contains($0) }
            return (profile, words.count { text.contains(" \($0) ") })
        }
        let best = scored.filter { $0.1 > 0 }.max { ($0.1, $0.0.thing.createdAt) < ($1.1, $1.0.thing.createdAt) }
        guard let (profile, _) = best else { return nil }

        let topic: ThingAnswer.Topic
        if [" warranty ", " covered ", " coverage ", " guarantee "].contains(where: { text.contains($0) }) {
            topic = .warranty
        } else if [" when ", " bought ", " buy ", " purchase ", " purchased ", " get ", " got "].contains(where: { text.contains($0) })
                    && text.contains(" when ") {
            topic = .bought
        } else if [" receipt ", " manual ", " paperwork ", " documents ", " document ", " show ", " invoice "].contains(where: { text.contains($0) }) {
            topic = .documents
        } else if [" worth ", " value ", " cost ", " pay ", " paid ", " price ", " how much "].contains(where: { text.contains($0) }) {
            topic = .value
        } else {
            topic = .overview
        }
        return ThingAnswer(profiles: [profile], topic: topic, isOutOfWarrantyList: false)
    }
}

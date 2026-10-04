import Foundation
import GRDB

/// One visit for the car, read from its receipt: what was done, and the
/// mileage if it's printed.
public struct CarService: Hashable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case oilChange, tireRotation, tires, brakes, alignment, battery, inspection, repair

        public var label: String {
            switch self {
            case .oilChange: "Oil change"
            case .tireRotation: "Tire rotation"
            case .tires: "Tires"
            case .brakes: "Brakes"
            case .alignment: "Alignment"
            case .battery: "Battery"
            case .inspection: "Inspection"
            case .repair: "Service"
            }
        }
    }

    public var record: Record
    public var day: Day
    public var mileage: Int?
    public var kinds: [Kind]
    public var amount: Money?
    public var id: UUID { record.id }
}

/// The car's history and what's next: the latest mileage, how fast it's
/// driven, and when the next oil change is due by date and by miles.
public struct CarSummary: Sendable {
    /// Newest first.
    public var services: [CarService]
    public var latestMileage: (miles: Int, day: Day)?
    public var milesPerDay: Double?
    public var lastOilChange: CarService?
    /// Six months after the last one, or sooner if the miles say so.
    public var nextOilChange: Day?
    public var nextOilChangeMiles: Int?

    /// Today's mileage, worked out from the driving rate.
    public func estimatedMileage(on day: Day) -> Int? {
        guard let latest = latestMileage else { return nil }
        guard let rate = milesPerDay else { return latest.miles }
        return latest.miles + Int((Double(latest.day.days(to: day)) * rate).rounded())
    }
}

extension ArchiveStore {
    /// Nil when nothing in the archive is a car service. `alsoInclude` are
    /// records put in the Car collection by hand: they count even when
    /// nothing in them says car.
    public func carSummary(oilChangeMiles: Int = 5000, oilChangeMonths: Int = 6,
                           alsoInclude: Set<UUID> = []) throws -> CarSummary? {
        let totals = try recordTotals()
        let services = try db.read { db in
            try Record.filter(Column("status") == IngestStatus.ready.rawValue)
                .filter([RecordKind.receipt, .document, .other, .bill].map(\.rawValue).contains(Column("kind")))
                .fetchAll(db)
                .compactMap { record -> CarService? in
                    let rows = Extractor.rows(of: try Self.storedPages(of: record.id, in: db))
                    let text = rows.map(\.text).joined(separator: "\n").lowercased()
                    let added = alsoInclude.contains(record.id)
                    guard added || Self.isAboutACar(text) else { return nil }
                    var kinds = Self.serviceKinds(in: text)
                    if kinds.isEmpty, added { kinds = [.repair] }
                    guard !kinds.isEmpty else { return nil }
                    return CarService(record: record, day: record.effectiveDay, mileage: Self.mileage(in: rows),
                                      kinds: kinds, amount: totals[record.id])
                }
        }
        guard !services.isEmpty else { return nil }
        let newestFirst = services.sorted { ($0.day, $0.record.createdAt) > ($1.day, $1.record.createdAt) }

        let readings = services.compactMap { service in service.mileage.map { (miles: $0, day: service.day) } }
            .sorted { $0.day < $1.day }
        var rate: Double?
        if let first = readings.first, let last = readings.last, first.day.days(to: last.day) >= 30, last.miles > first.miles {
            rate = Double(last.miles - first.miles) / Double(first.day.days(to: last.day))
        }

        let lastOil = newestFirst.first { $0.kinds.contains(.oilChange) }
        var next: Day?
        var nextMiles: Int?
        if let lastOil {
            next = lastOil.day.addingMonths(oilChangeMonths)
            if let miles = lastOil.mileage {
                nextMiles = miles + oilChangeMiles
                if let rate, rate > 0 {
                    let byMiles = lastOil.day.adding(days: Int((Double(oilChangeMiles) / rate).rounded()))
                    if let current = next, byMiles < current { next = byMiles }
                }
            }
        }
        return CarSummary(services: newestFirst, latestMileage: readings.last, milesPerDay: rate,
                          lastOilChange: lastOil, nextOilChange: next, nextOilChangeMiles: nextMiles)
    }

    /// AA batteries from CVS aren't a car battery: only paperwork that's
    /// about a vehicle counts.
    static func isAboutACar(_ text: String) -> Bool {
        ["vehicle", "odometer", "mileage", "vin", "oil change", "jiffy lube", "valvoline", "firestone", "midas", "pep boys",
         "tire", "automotive", "auto repair", "auto service", "mechanic", "service advisor", "repair order", "lube", "dealership"]
            .contains { text.contains($0) }
    }

    static func serviceKinds(in text: String) -> [CarService.Kind] {
        var kinds: [CarService.Kind] = []
        if ["oil change", "lube oil", "oil & filter", "oil and filter", "synthetic oil", "conventional oil", "full synthetic",
            "synthetic blend", "oil filter"].contains(where: text.contains) { kinds.append(.oilChange) }
        if text.contains("rotation") || text.contains("rotate") { kinds.append(.tireRotation) }
        if ["new tire", "tire install", "mount and balance", "mount & balance", "tires "].contains(where: text.contains)
            || text.range(of: "\\b\\d tires?\\b", options: .regularExpression) != nil { kinds.append(.tires) }
        if text.contains("brake") { kinds.append(.brakes) }
        if text.contains("alignment") { kinds.append(.alignment) }
        if text.contains("battery") { kinds.append(.battery) }
        if text.contains("inspection") || text.contains("emissions") { kinds.append(.inspection) }
        if kinds.isEmpty, ["repair order", "service invoice", "labor", "mechanic", "diagnostic"].contains(where: text.contains) {
            kinds.append(.repair)
        }
        return kinds
    }

    /// "Mileage: 45,210", "ODOMETER 45210", "Miles In 45,210", "45,210 mi".
    static func mileage(in rows: [TextRow]) -> Int? {
        let labelled = DayParser.regex("(?:mileage|odometer|odo|miles in|mileage in|miles)\\s*(?:in|out)?\\s*[:#]?\\s*(\\d{1,3}(?:,\\d{3})+|\\d{3,7})\\b")
        let suffixed = DayParser.regex("\\b(\\d{1,3}(?:,\\d{3})+|\\d{4,7})\\s*(?:mi|miles)\\b")
        var found: [Int] = []
        for row in rows {
            let ns = row.text as NSString
            for regex in [labelled, suffixed] {
                for match in regex.matches(in: row.text, range: NSRange(location: 0, length: ns.length)) {
                    let digits = ns.substring(with: match.range(at: 1)).filter(\.isNumber)
                    if let miles = Int(digits), (100...999_999).contains(miles) { found.append(miles) }
                }
            }
        }
        return found.max()
    }
}

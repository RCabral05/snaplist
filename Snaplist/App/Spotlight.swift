import ArchiveCore
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Records in the iPhone's own search, when turned on in Settings. Off by
/// default: Spotlight shows results without Snaplist's Face ID lock, so
/// only names, categories, dates and totals go in, never the text of a page.
enum Spotlight {
    static let settingKey = "showInSpotlight"
    static let domain = "records"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: settingKey)
    }

    /// Replaces what's indexed with `records`. Cheap: Spotlight updates by id.
    static func index(_ records: [Record], totals: [UUID: Money]) async {
        // IDs and policies stay out of Spotlight entirely.
        let items = records.filter { $0.status == .ready && $0.kind != .identity }.map { record in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = record.title
            var description = "\(record.kind.label) · \(record.effectiveDay.date().formatted(date: .abbreviated, time: .omitted))"
            if let total = totals[record.id] { description += " · \(total.formatted)" }
            attributes.contentDescription = description
            attributes.keywords = [record.kind.label, record.kind.pluralLabel]
            let item = CSSearchableItem(uniqueIdentifier: record.id.uuidString, domainIdentifier: domain,
                                        attributeSet: attributes)
            item.expirationDate = .distantFuture
            return item
        }
        let index = CSSearchableIndex.default()
        try? await index.deleteSearchableItems(withDomainIdentifiers: [domain])
        guard !items.isEmpty else { return }
        try? await index.indexSearchableItems(items)
    }

    static func removeAll() async {
        try? await CSSearchableIndex.default().deleteAllSearchableItems()
    }

    /// The record a Spotlight result points at.
    static func recordId(from activity: NSUserActivity) -> UUID? {
        (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(UUID.init(uuidString:))
    }
}

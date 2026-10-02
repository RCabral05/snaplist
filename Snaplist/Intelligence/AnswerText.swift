import ArchiveCore
import Foundation

extension SpendingAnswer {
    /// "fuel spending at Shell", without the period.
    var subject: String {
        var subject = query.categories.isEmpty
            ? "spending" : query.categories.map(\.label).sorted().joined(separator: " and ").lowercased() + " spending"
        if !query.merchantTerms.isEmpty {
            subject += " at \(query.merchantTerms.joined(separator: " or ").capitalized)"
        }
        return subject
    }

    /// "fuel spending in September 2026", "spending at Costco this year".
    var scope: String {
        guard let label = query.rangeLabel else { return subject }
        let relative = label.hasPrefix("this") || label.hasPrefix("the") || label == "today" || label == "yesterday"
        return subject + (relative ? " \(label)" : " in \(label)")
    }
}

/// An answer as one or two sentences, for Siri and Shortcuts. The same
/// answer the Ask screen shows, numbers and all, just without the list.
enum AnswerText {
    static func spoken(_ result: AskResult) -> String {
        switch result {
        case .spending(let answer):
            guard !answer.counted.isEmpty else {
                var text = "I couldn't find any \(answer.scope) in your archive."
                if let month = answer.otherMonths.first {
                    text += " The latest month with some is \(month.label): \(amounts(month.totals))."
                }
                return text
            }
            let count = answer.counted.count == 1 ? "1 amount" : "\(answer.counted.count) amounts"
            var text = "\(answer.scope.prefix(1).uppercased())\(answer.scope.dropFirst()): \(amounts(answer.totals)), from \(count)."
            if answer.notes.contains(where: { $0.hasPrefix("No card or bank statement") }) {
                text += " No statement covers that period, so only receipts and bills are counted."
            }
            return text
        case .whereIs(let hits, _):
            guard let hit = hits.first else { return "I couldn't find a note about that." }
            let said = hit.snippet.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return said.isEmpty ? "Your best match is “\(hit.record.title)”." : "From “\(hit.record.title)”: \(said)"
        case .expiry(let found, _):
            guard let first = found.first else { return "I couldn't find an expiry date for that." }
            let day = first.day.date().formatted(date: .long, time: .omitted)
            return first.isCalculated
                ? "“\(first.record.title)” runs out around \(day), worked out from the purchase date and the coverage printed on it."
                : "“\(first.record.title)” expires on \(day)."
        case .lastBought(let found, let terms):
            guard let latest = found.first else { return "No saved receipt lists \(terms.joined(separator: " "))." }
            return "You last bought \(latest.transaction.memo) on \(latest.day.date().formatted(date: .long, time: .omitted)) at \(latest.transaction.merchant), for \(latest.transaction.money.formatted)."
        case .thing(let answer):
            guard let profile = answer.profiles.first else {
                return answer.isOutOfWarrantyList ? "Everything you've saved is still covered." : "I couldn't find that."
            }
            if answer.isOutOfWarrantyList {
                return "\(answer.profiles.count) things are out of warranty, including \(profile.thing.name)."
            }
            switch answer.topic {
            case .bought:
                return profile.thing.purchased.map { "You bought \(profile.thing.name) on \($0.date().formatted(date: .long, time: .omitted))\(profile.thing.store.isEmpty ? "" : " at \(profile.thing.store)")." }
                    ?? "There's no purchase date saved for \(profile.thing.name)."
            case .warranty:
                switch profile.warranty(on: Day(.now)) {
                case .covered(let until): return "Yes, \(profile.thing.name) is covered until \(until.date().formatted(date: .long, time: .omitted))."
                case .ended(let on): return "No, the warranty on \(profile.thing.name) ended on \(on.date().formatted(date: .long, time: .omitted))."
                case .unknown: return "There's no warranty date saved for \(profile.thing.name)."
                }
            case .value:
                return profile.thing.value.map { "\(profile.thing.name) cost \($0.formatted)." } ?? "There's no price saved for \(profile.thing.name)."
            case .documents, .overview:
                return "\(profile.thing.name) has \(profile.links.count) documents in Snaplist. Open the app to see them."
            }
        case .priceHistory(let history, let terms):
            guard let history, let latest = history.latest else { return "No saved receipt lists \(terms.joined(separator: " "))." }
            return "Last time, \(latest.transaction.money.formatted) at \(latest.transaction.merchant). On average \(Money(cents: history.averageCents, currency: history.currency).formatted) over \(history.points.count) times."
        case .collection(let collection, let records):
            return "\(collection.name) has \(records.count) records."
        case .records(let tagged):
            switch tagged.records.count {
            case 0: return "Nothing is tagged with \(tagged.tags.map(\.name).joined(separator: " and "))."
            case 1: return "One record: “\(tagged.records[0].title)”."
            default:
                let names = tagged.records.prefix(3).map { "“\($0.title)”" }.joined(separator: ", ")
                return "\(tagged.records.count) records, including \(names)."
            }
        case .search(let hits, let text):
            switch hits.count {
            case 0: return "Nothing in your archive mentions “\(text)”."
            case 1: return "One record mentions it: “\(hits[0].record.title)”."
            default:
                let names = hits.prefix(3).map { "“\($0.record.title)”" }.joined(separator: ", ")
                return "\(hits.count) records mention it, including \(names)."
            }
        }
    }

    static func amounts(_ totals: [Money]) -> String {
        totals.map(\.formatted).joined(separator: " and ")
    }
}

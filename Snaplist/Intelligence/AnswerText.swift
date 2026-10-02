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

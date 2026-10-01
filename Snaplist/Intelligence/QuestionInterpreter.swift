import ArchiveCore
import Foundation
import FoundationModels

/// Reads questions the built-in rules don't understand, with Apple's
/// on-device model where Apple Intelligence is on. The model only fills in
/// fixed fields (what kind of question, which categories, merchants and
/// period); ArchiveCore turns those into a query and adds up the answer with
/// ordinary code. Without Apple Intelligence, questions are read by the rules
/// alone and everything else works the same.
enum QuestionInterpreter {
    static let settingKey = "useAppleIntelligence"

    /// On unless turned off in Settings.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// For Settings: why it is or isn't in use.
    static var status: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Apple Intelligence reads questions the built-in rules don't, on this iPhone. Totals are always added up by Snaplist itself."
        case .unavailable(.deviceNotEligible):
            return "This iPhone doesn't support Apple Intelligence, so questions are read by Snaplist's built-in rules."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in the Settings app to have it read questions the built-in rules don't."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still getting ready on this iPhone. Until then, questions are read by the built-in rules."
        case .unavailable:
            return "Apple Intelligence isn't available right now, so questions are read by the built-in rules."
        }
    }

    static let instructions = """
        You read one question a person asks about their own saved receipts, bills, bank statements, \
        warranties and voice notes, and fill in the fields describing it. Never answer the question. \
        Use spending for questions about money spent or paid, whereIs for where something was put or kept, \
        expiry for when a warranty, policy or document runs out, and search for anything else. \
        Only list categories, merchants and words that are in the question.
        """

    /// Nil when Apple Intelligence is off, unavailable, or can't make sense of it.
    @concurrent
    static func interpret(_ question: String) async -> Interpretation? {
        guard isEnabled, isAvailable else { return nil }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: question, generating: ReadQuestion.self)
            return response.content.interpretation
        } catch {
            return nil
        }
    }
}

@Generable
struct ReadQuestion {
    @Guide(description: "What kind of question it is")
    var kind: QuestionKind

    @Guide(description: "Spending categories the question is about; empty if none is named")
    var categories: [QuestionCategory]

    @Guide(description: "Store, company or service names in the question, as written; empty if none")
    var merchants: [String]

    @Guide(description: "For whereIs and expiry questions, the words naming the thing asked about, such as passport or TV; otherwise empty")
    var subject: [String]

    @Guide(description: "The time period the question is about; anyTime if none is named")
    var period: QuestionPeriod

    @Guide(description: "For namedMonth, the month's number from 1 to 12; otherwise 0")
    var month: Int

    @Guide(description: "A four-digit year if the question names one; otherwise 0")
    var year: Int

    var interpretation: Interpretation {
        let named = year > 1900 ? year : nil
        let resolved: Interpretation.Period = switch period {
        case .anyTime: .anyTime
        case .thisMonth: .thisMonth
        case .lastMonth: .lastMonth
        case .thisYear: .thisYear
        case .lastYear: .lastYear
        case .namedMonth: .month(month, year: named)
        case .namedYear: named.map { .year($0) } ?? .anyTime
        }
        let intent: Interpretation.Intent = switch kind {
        case .spending: .spending
        case .whereIs: .whereIs
        case .expiry: .expiry
        case .search: .search
        }
        return Interpretation(intent: intent, categories: Set(categories.map(\.category)), merchants: merchants,
                              subject: subject, period: resolved)
    }
}

@Generable
enum QuestionKind {
    case spending, whereIs, expiry, search
}

@Generable
enum QuestionCategory {
    case fuel, groceries, eatingOut, pharmacy, utilities, subscriptions, shopping, travel

    var category: SpendCategory {
        switch self {
        case .fuel: .fuel
        case .groceries: .groceries
        case .eatingOut: .dining
        case .pharmacy: .pharmacy
        case .utilities: .utilities
        case .subscriptions: .subscriptions
        case .shopping: .shopping
        case .travel: .travel
        }
    }
}

@Generable
enum QuestionPeriod {
    case anyTime, thisMonth, lastMonth, thisYear, lastYear, namedMonth, namedYear
}

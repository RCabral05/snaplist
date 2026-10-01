import AppIntents
import ArchiveCore
import Foundation

/// "Hey Siri, ask Snaplist": any question the Ask screen takes, answered
/// from the archive on this iPhone. Needs the iPhone unlocked; with
/// Snaplist's own lock on, it opens Snaplist (which asks for Face ID) and
/// shows the answer there instead of speaking it.
struct AskSnaplistIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Ask Snaplist"
    static let description = IntentDescription(
        "Answers a question from the receipts, statements, bills and notes saved in Snaplist. Worked out on this iPhone.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Question", requestValueDialog: "What would you like to know?")
    var question: String

    init() {}

    init(question: String) {
        self.question = question
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try SharedModel.model()
        if AppLock.isEnabledSetting {
            let question = question
            throw needsToContinueInForegroundError("Snaplist is locked. Unlock it to see the answer.") {
                model.pendingQuestion = question
            }
        }
        let result = await model.ask(question)
        return .result(dialog: "\(AnswerText.spoken(result))")
    }
}

/// "How much did I spend on gas in Snaplist?" A fixed question with a
/// category and period to pick, so it works as a Siri phrase and a widget-
/// style shortcut.
struct SpendingIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Check Spending"
    static let description = IntentDescription("Adds up what you spent on something, from the amounts saved in Snaplist.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Category", requestValueDialog: "Spending on what?")
    var category: SpendingCategoryOption

    @Parameter(title: "Period", default: .thisMonth)
    var period: SpendingPeriodOption

    static var parameterSummary: some ParameterSummary {
        Summary("How much did I spend on \(\.$category) \(\.$period)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try SharedModel.model()
        // The same words someone would type on the Ask screen, read by the
        // same rules.
        let question = "How much did I spend \(category.phrase) \(period.phrase)"
        if AppLock.isEnabledSetting {
            throw needsToContinueInForegroundError("Snaplist is locked. Unlock it to see the answer.") {
                model.pendingQuestion = question
            }
        }
        let result = await model.ask(question)
        return .result(dialog: "\(AnswerText.spoken(result))")
    }
}

enum SpendingCategoryOption: String, AppEnum {
    case gas, groceries, eatingOut, pharmacy, utilities, subscriptions, shopping, travel, everything

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Spending Category"
    static let caseDisplayRepresentations: [SpendingCategoryOption: DisplayRepresentation] = [
        .gas: "Gas",
        .groceries: "Groceries",
        .eatingOut: "Eating Out",
        .pharmacy: "Pharmacy",
        .utilities: "Utilities",
        .subscriptions: "Subscriptions",
        .shopping: "Shopping",
        .travel: "Travel",
        .everything: "Everything",
    ]

    var phrase: String {
        switch self {
        case .gas: "on gas"
        case .groceries: "on groceries"
        case .eatingOut: "on eating out"
        case .pharmacy: "on pharmacy"
        case .utilities: "on utilities"
        case .subscriptions: "on subscriptions"
        case .shopping: "on shopping"
        case .travel: "on travel"
        case .everything: ""
        }
    }
}

enum SpendingPeriodOption: String, AppEnum {
    case thisMonth, lastMonth, thisYear, lastYear, allTime

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    static let caseDisplayRepresentations: [SpendingPeriodOption: DisplayRepresentation] = [
        .thisMonth: "this month",
        .lastMonth: "last month",
        .thisYear: "this year",
        .lastYear: "last year",
        .allTime: "in total",
    ]

    var phrase: String {
        switch self {
        case .thisMonth: "this month"
        case .lastMonth: "last month"
        case .thisYear: "this year"
        case .lastYear: "last year"
        case .allTime: ""
        }
    }
}

struct SnaplistShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskSnaplistIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question",
                "Search \(.applicationName)",
            ],
            shortTitle: "Ask Snaplist",
            systemImageName: "sparkle.magnifyingglass")
        AppShortcut(
            intent: SpendingIntent(),
            phrases: [
                "How much did I spend on \(\.$category) in \(.applicationName)",
                "Check \(\.$category) spending in \(.applicationName)",
                "\(.applicationName) \(\.$category) spending",
            ],
            shortTitle: "Check Spending",
            systemImageName: "dollarsign.circle")
    }
}

/// The one archive, shared by the app's window and by Siri and Shortcuts,
/// which can run before any window exists.
@MainActor
enum SharedModel {
    static let opened: Result<AppModel, any Error> = Result { try AppModel.live() }

    static func model() throws -> AppModel {
        try opened.get()
    }
}

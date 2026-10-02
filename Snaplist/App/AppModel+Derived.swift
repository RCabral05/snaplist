import ArchiveCore
import Foundation

/// Everything worked out from the whole archive: month totals, repeating
/// charges, what's coming up, budgets, the inventory total, tax years.
/// Computed off the main thread once changes settle, then shared by Home,
/// Spending, reminders, budget alerts and widgets, so a 20-photo import
/// doesn't recompute it dozens of times while scrolling.
struct Derived: Sendable {
    var overview: SpendingOverview?
    var recurring: [RecurringCharge] = []
    var upcoming: [UpcomingDate] = []
    var budgets: [BudgetStatus] = []
    var inventory: InventorySummary?
    var taxYears: [Int] = []
    var importantDocuments: [ImportantDocument] = []
}

extension AppModel {
    /// Recomputes `derived` shortly after the last change, then brings
    /// reminders, budget alerts, widgets and Spotlight up to date.
    func refreshDerived() {
        derivedTask?.cancel()
        let store = archive.store
        let today = Day(.now)
        let month = budgetMonth
        derivedTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let fresh = await Self.compute(store, today: today, month: month)
            guard !Task.isCancelled else { return }
            derived = fresh
            derivedRevision += 1
            await Reminders.schedule(fresh.upcoming)
            checkBudgets()
            updateWidgets()
            updateSpotlight()
        }
    }

    @concurrent
    private static func compute(_ store: ArchiveStore, today: Day, month: DayRange) async -> Derived {
        Derived(
            overview: try? store.spendingOverview(),
            recurring: (try? store.recurringCharges()) ?? [],
            upcoming: (try? store.upcomingDates(from: today)) ?? [],
            budgets: (try? store.budgetStatus(in: month)) ?? [],
            inventory: try? store.inventorySummary(),
            taxYears: (try? store.taxYears()) ?? [],
            importantDocuments: (try? store.importantDocuments()) ?? [])
    }
}

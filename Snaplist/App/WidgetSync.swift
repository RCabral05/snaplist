import ArchiveCore
import Foundation
import WidgetKit

/// Writes the few numbers the widgets show and asks them to redraw.
extension AppModel {
    func updateWidgets() {
        widgetTask?.cancel()
        widgetTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            try? makeWidgetSnapshot().save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func makeWidgetSnapshot() -> WidgetSnapshot {
        let today = Day(.now)
        let overview = spendingOverview()
        // This month if it has anything, else the latest month that does.
        let month = overview?.months.last { $0.range.contains(today) && $0.count > 0 }
            ?? overview?.months.last { $0.count > 0 }
        let currency = overview?.currency ?? "USD"
        let total = max(1, month?.totalCents ?? 1)
        let categories = (month?.byCategory ?? [:])
            .filter { $0.value > 0 && $0.key != .other }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { WidgetSnapshot.Category(name: $0.key.label, amount: Money(cents: $0.value, currency: currency).formattedWhole,
                                           share: Double($0.value) / Double(total)) }

        var upcoming = upcomingDates().map { date in
            WidgetSnapshot.Upcoming(title: date.title, date: date.day.date(), amount: date.amount?.formatted, symbol: date.symbol)
        }
        for charge in recurringCharges() where charge.nextExpected >= today && charge.nextExpected <= today.adding(days: 30) {
            upcoming.append(WidgetSnapshot.Upcoming(
                title: "\(charge.merchant) renews", date: charge.nextExpected.date(),
                amount: Money(cents: charge.typicalCents, currency: charge.currency).formatted, symbol: "repeat"))
        }
        upcoming.sort { $0.date < $1.date }

        let budgets = budgetStatus().sorted { $0.fraction > $1.fraction }.map { status in
            WidgetSnapshot.BudgetLine(name: status.budget.category?.label ?? "All spending",
                                      spent: Money(cents: status.spentCents, currency: status.currency).formattedWhole,
                                      limit: Money(cents: status.budget.limitCents, currency: status.currency).formattedWhole,
                                      fraction: status.fraction)
        }

        return WidgetSnapshot(
            monthLabel: month.map { $0.label.components(separatedBy: " ").first ?? $0.label } ?? "This month",
            monthTotal: Money(cents: month?.totalCents ?? 0, currency: currency).formattedWhole,
            categories: Array(categories), upcoming: Array(upcoming.prefix(5)), budgets: Array(budgets.prefix(3)),
            theme: Theme.current.id.rawValue, updated: .now)
    }
}

import ArchiveCore
import Foundation
import UserNotifications

/// Notifications a few days before a bill is due and a month before a
/// warranty ends, when turned on in Settings. Scheduled on this iPhone from
/// the dates read off saved records; nothing is sent anywhere.
enum Reminders {
    static let settingKey = "remindersEnabled"
    private static let prefix = "snaplist.reminder."

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: settingKey)
    }

    /// Asks iOS for permission. False if the person said no.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces every scheduled reminder with ones for `dates`; with
    /// reminders off, just removes them.
    static func schedule(_ dates: [UpcomingDate], subscriptions: [Subscription] = [], car: CarSummary? = nil,
                         now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard isEnabled else { return }

        // On the 1st of every month: last month's recap.
        let recap = UNMutableNotificationContent()
        recap.title = "Your monthly recap is ready"
        recap.body = "Where last month's money went, what renewed and what changed. Tap to see it."
        recap.sound = .default
        recap.userInfo = ["link": SnaplistLink.recap.rawValue]
        try? await center.add(UNNotificationRequest(
            identifier: prefix + "recap", content: recap,
            trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(day: 1, hour: 9, minute: 5), repeats: true)))

        let calendar = Calendar.current
        var added = 1

        /// 9am on `day`, `daysBefore` ahead of it, if that's still to come.
        func nineAM(_ day: Day, daysBefore: Int) -> Date? {
            guard let date = calendar.date(byAdding: .day, value: -daysBefore, to: day.date(calendar: calendar)),
                  let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date), fire > now else { return nil }
            return fire
        }
        func add(_ id: String, _ fire: Date, _ title: String, _ body: String, recordId: UUID?) async {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let recordId { content.userInfo = ["recordId": recordId.uuidString] }
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            try? await center.add(UNNotificationRequest(identifier: prefix + id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }

        // Subscriptions asked to be reminded about, and trials, two days ahead.
        for subscription in subscriptions where subscription.remind {
            guard let next = subscription.nextCharge, let fire = nineAM(next, daysBefore: 2), added < 50 else { continue }
            let price = subscription.priceCents.map { Money(cents: $0, currency: subscription.currency).formatted }
            let isTrial = subscription.trialEnds == next
            await add("sub.\(subscription.key)", fire,
                      isTrial ? "\(subscription.name) trial ends in 2 days" : "\(subscription.name) renews in 2 days",
                      isTrial ? "After that it charges\(price.map { " \($0)" } ?? ""). Cancel before then if you don't want it."
                              : "\(price ?? "It") will be charged \(next.date(calendar: calendar).formatted(.dateTime.month(.abbreviated).day())).",
                      recordId: subscription.charge?.latest.record.id)
            added += 1
        }

        // The car's next oil change, the morning it's due.
        if let car, let due = car.nextOilChange, let fire = nineAM(due, daysBefore: 0) {
            await add("car.oil", fire, "Oil change due",
                      car.nextOilChangeMiles.map { "Due around \($0.formatted()) miles or today, whichever comes first." }
                          ?? "Six months since the last one.",
                      recordId: car.lastOilChange?.record.id)
            added += 1
        }
        for date in dates {
            // iOS keeps 64 per app; leave room.
            guard added < 50 else { break }
            let daysBefore = switch date.kind {
            case .warrantyEnds: 30
            case .renewal: 60
            case .billDue, .returnBy: 3
            }
            guard var fire = calendar.date(byAdding: .day, value: -daysBefore, to: date.day.date(calendar: calendar)),
                  let nineAM = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: fire) else { continue }
            fire = nineAM
            if fire <= now {
                // Too late for the usual notice: the morning of, if that's still ahead.
                guard let morningOf = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date.day.date(calendar: calendar)),
                      morningOf > now else { continue }
                fire = morningOf
            }

            let content = UNMutableNotificationContent()
            let when = date.day.date(calendar: calendar).formatted(.dateTime.month(.abbreviated).day())
            switch date.kind {
            case .billDue:
                content.title = "\(date.record.title) is due \(when)"
                content.body = date.amount.map { "\($0.formatted) is due. Tap to see the bill." } ?? "Tap to see it in Snaplist."
            case .warrantyEnds:
                content.title = "A warranty ends \(when)"
                content.body = "“\(date.record.title)” stops covering you then. Tap to see it."
            case .renewal:
                content.title = "Time to renew: expires \(when)"
                content.body = "“\(date.record.title)” runs out in about two months. Tap to see it."
            case .returnBy:
                content.title = "Last day to return: \(when)"
                content.body = "The return window for “\(date.record.title)” closes then. Tap to see the receipt."
            }
            content.sound = .default
            content.userInfo = ["recordId": date.record.id.uuidString]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(identifier: prefix + date.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
            added += 1
        }
    }
}

extension Reminders {
    /// Right away: a new bill or subscription costs more (or less) than last time.
    static func notifyPriceChange(_ change: PriceChange) async {
        let content = UNMutableNotificationContent()
        let up = change.deltaCents > 0
        let delta = Money(cents: abs(change.deltaCents), currency: change.currency).formatted
        content.title = "\(change.merchant) \(change.kind == .bill ? "bill" : "charge") \(up ? "went up" : "went down")"
        content.body = await MainActor.run { AppLock.isEnabledSetting }
            ? "Open Snaplist to see what changed."
            : "\(up ? "Up" : "Down") \(delta) (\(abs(change.percent))%) from last time. Tap to see what changed."
        content.sound = .default
        content.userInfo = ["recordId": change.latest.record.id.uuidString]
        let request = UNNotificationRequest(identifier: "snaplist.change.\(change.id)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Right away: a budget passed 80% or 100% of its limit this month.
    static func notifyBudget(_ status: BudgetStatus, threshold: Int) async {
        let content = UNMutableNotificationContent()
        let name = status.budget.category?.label ?? "spending"
        let limit = Money(cents: status.budget.limitCents, currency: status.currency).formatted
        content.title = threshold >= 100 ? "Over your \(name.lowercased()) budget" : "\(threshold)% of your \(name.lowercased()) budget"
        // With Snaplist locked, amounts stay in the app.
        content.body = await MainActor.run { AppLock.isEnabledSetting }
            ? "Open Snaplist to see this month's budgets."
            : "\(Money(cents: status.spentCents, currency: status.currency).formatted) of \(limit) this month."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "snaplist.budget.\(status.id).\(threshold)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Opens the record a reminder is about when it's tapped, and shows
/// reminders that arrive while Snaplist is open.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationRouter()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let link = (info["link"] as? String).flatMap(SnaplistLink.init(rawValue:)) {
            await MainActor.run { (try? SharedModel.model())?.pendingLink = link }
            return
        }
        let id = (info["recordId"] as? String).flatMap(UUID.init(uuidString:))
        guard let id else { return }
        await MainActor.run {
            (try? SharedModel.model())?.pendingRecordId = id
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

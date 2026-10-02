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
    static func schedule(_ dates: [UpcomingDate], now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard isEnabled else { return }

        let calendar = Calendar.current
        var added = 0
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
        let id = (response.notification.request.content.userInfo["recordId"] as? String).flatMap(UUID.init(uuidString:))
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

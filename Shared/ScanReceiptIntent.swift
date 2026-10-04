import AppIntents
import Foundation

/// Opens Snaplist straight to the scanner. The Control Center and Lock Screen
/// control runs it, and it can be put on the Action button.
struct ScanReceiptIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan a Receipt"
    static let description = IntentDescription("Opens Snaplist's scanner.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LinkRequests.post(.scan)
        return .result()
    }
}

/// A link asked for from outside the app's own screens (a control, a
/// shortcut), handed to the app once it's running.
@MainActor
enum LinkRequests {
    static let notification = Notification.Name("SnaplistLinkRequest")
    static var pending: SnaplistLink?

    static func post(_ link: SnaplistLink) {
        pending = link
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func take() -> SnaplistLink? {
        defer { pending = nil }
        return pending
    }
}

/// Where the share extension leaves what's shared, for the app to import.
enum SharedInbox {
    static let appGroup = "group.com.rcabral.snaplist"

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }
}

import CoreSpotlight
import SwiftUI
import UIKit
import UserNotifications

@main
struct SnaplistApp: App {
    // Shared with Siri and Shortcuts, which can start the app without a window.
    @State private var opened = SharedModel.opened
    @State private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            switch opened {
            case .success(let model):
                ZStack {
                    // Not rendered at all while locked, so nothing it presents
                    // (a sheet, an alert, the scanner) can show above the lock.
                    if lock.isLocked {
                        LockView()
                    } else {
                        MainTabs()
                    }
                }
                .overlay {
                    if lock.isEnabled && !lock.isLocked && scenePhase != .active {
                        PrivacyCover()
                    }
                }
                .environment(model)
                .environment(lock)
                .tint(Theme.accent)
                .preferredColorScheme(Theme.current.colorScheme ?? DemoData.forcedColorScheme)
                // On the container, so locking and unlocking doesn't restart it.
                .task { await model.start() }
                // Shared from another app; imported even while locked, since
                // adding a file reveals nothing.
                .onOpenURL { url in model.importShared(url) }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    model.pendingRecordId = Spotlight.recordId(from: activity)
                }
                .onChange(of: scenePhase) { _, phase in
                    lock.sceneChanged(to: phase)
                    if phase == .active {
                        model.importInbox()
                        model.resumePending()
                        model.syncBanksIfDue()
                    }
                }
            case .failure(let error):
                ContentUnavailableView(
                    "Couldn't open your archive",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription))
            }
        }
    }
}

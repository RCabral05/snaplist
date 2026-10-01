import CoreSpotlight
import SwiftUI
import UIKit

@main
struct SnaplistApp: App {
    // Shared with Siri and Shortcuts, which can start the app without a window.
    @State private var opened = SharedModel.opened
    @State private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // New York for navigation titles, to match the headings.
        let appearance = UINavigationBar.appearance()
        if let large = UIFont.preferredFont(forTextStyle: .largeTitle).fontDescriptor
            .withDesign(.serif)?.withSymbolicTraits(.traitBold) {
            appearance.largeTitleTextAttributes = [.font: UIFont(descriptor: large, size: 0)]
        }
        if let inline = UIFont.preferredFont(forTextStyle: .headline).fontDescriptor.withDesign(.serif) {
            appearance.titleTextAttributes = [.font: UIFont(descriptor: inline, size: 0)]
        }
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
                        RecordListView()
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
                .preferredColorScheme(DemoData.forcedColorScheme)
                // On the container, so locking and unlocking doesn't restart it.
                .task { await model.start() }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    model.pendingRecordId = Spotlight.recordId(from: activity)
                }
                .onChange(of: scenePhase) { _, phase in
                    lock.sceneChanged(to: phase)
                    if phase == .active { model.resumePending() }
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

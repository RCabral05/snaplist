import SwiftUI

@main
struct SnaplistApp: App {
    @State private var opened: Result<AppModel, any Error> = Result { try AppModel.live() }
    @State private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

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
                // On the container, so locking and unlocking doesn't restart it.
                .task { await model.start() }
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

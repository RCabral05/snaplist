import SwiftUI

@main
struct SnaplistApp: App {
    @State private var opened: Result<AppModel, any Error> = Result { try AppModel.live() }
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            switch opened {
            case .success(let model):
                RecordListView()
                    .environment(model)
                    .task { await model.start() }
                    .onChange(of: scenePhase) { _, phase in
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

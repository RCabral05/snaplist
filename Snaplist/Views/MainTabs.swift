import ArchiveCore
import PhotosUI
import SwiftUI
import VisionKit

/// The ways in, shared by every tab: the add bar under the tabs, the
/// welcome screen, and Home's empty state all start the same flows.
@MainActor @Observable
final class AddFlow {
    var isScanning = false
    var isPickingPhotos = false
    var isPickingFiles = false
    var isRecordingNote = false

    /// False on the simulator and on devices without a camera.
    var canScan: Bool { VNDocumentCameraViewController.isSupported }
}

/// Home, Library, Spending and Ask as tabs, with the ways to add something
/// always just above them.
struct MainTabs: View {
    @Environment(AppModel.self) private var model

    enum Tab: Hashable {
        case home, library, spending, ask
    }

    @State private var selection: Tab = .home
    @State private var addFlow = AddFlow()
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isShowingSettings = false
    @State private var libraryPath: [RecordListView.Destination] = []
    /// A question handed to Ask from Home's field or from Siri; the token
    /// restarts Ask with it.
    @State private var askQuestion = ""
    @State private var askToken = 0

    var body: some View {
        @Bindable var addFlow = addFlow

        TabView(selection: $selection) {
            SwiftUI.Tab("Home", systemImage: "house", value: Tab.home) {
                HomeView(showSettings: { isShowingSettings = true }, ask: ask, open: { selection = $0 })
            }
            SwiftUI.Tab("Library", systemImage: "square.grid.2x2", value: Tab.library) {
                RecordListView(path: $libraryPath)
            }
            SwiftUI.Tab("Spending", systemImage: "chart.bar.xaxis", value: Tab.spending) {
                OverviewView(showsDone: false)
            }
            SwiftUI.Tab("Ask", systemImage: "sparkle.magnifyingglass", value: Tab.ask) {
                AskView(question: askQuestion, showsDone: false)
                    .id(askToken)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            AddBar()
        }
        .environment(addFlow)
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        .sheet(isPresented: $addFlow.isRecordingNote) {
            VoiceNoteRecorder { url in model.importVoiceNote(url) }
        }
        .fullScreenCover(isPresented: $addFlow.isScanning) {
            DocumentScanner { images in
                addFlow.isScanning = false
                model.importScan(images)
            } onCancel: {
                addFlow.isScanning = false
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $addFlow.isPickingPhotos, selection: $photoSelection,
                      maxSelectionCount: 20, matching: .images)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task { await model.importPhotos(items) }
        }
        .fileImporter(isPresented: $addFlow.isPickingFiles, allowedContentTypes: [.pdf, .image],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.importFiles(urls)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .overlay(alignment: .top) {
            if let notice = model.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { model.notice = nil }
                    }
            }
        }
        .animation(.snappy, value: model.notice)
        .alert("Something went wrong", isPresented: hasError) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: model.records.count) { old, new in new > old }
        // From Siri, when the lock meant the answer had to be shown here.
        .task(id: model.pendingQuestion) {
            guard let question = model.pendingQuestion else { return }
            model.pendingQuestion = nil
            isShowingSettings = false
            ask(question)
        }
        // From Spotlight or a reminder.
        .task(id: model.pendingRecordId) { openPendingRecord() }
        .onChange(of: model.records) { openPendingRecord() }
    }

    private func ask(_ question: String) {
        askQuestion = question
        askToken += 1
        selection = .ask
    }

    private func openPendingRecord() {
        guard let id = model.pendingRecordId,
              let record = model.records.first(where: { $0.id == id }) else { return }
        model.pendingRecordId = nil
        isShowingSettings = false
        selection = .library
        libraryPath = [RecordListView.Destination(record: record)]
    }

    private var hasError: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

/// Scan, Photos, Files and Voice, above the tabs. Collapses to one Add menu
/// when the tab bar shrinks.
private struct AddBar: View {
    @Environment(AddFlow.self) private var addFlow
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if placement == .inline {
            Menu {
                actions
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("add")
        } else {
            HStack(spacing: 0) {
                if addFlow.canScan {
                    item("Scan", "doc.viewfinder") { addFlow.isScanning = true }
                }
                item("Photos", "photo.on.rectangle") { addFlow.isPickingPhotos = true }
                item("Files", "folder") { addFlow.isPickingFiles = true }
                item("Voice", "mic") { addFlow.isRecordingNote = true }
            }
            .accessibilityIdentifier("add")
        }
    }

    @ViewBuilder private var actions: some View {
        if addFlow.canScan {
            Button("Scan Document", systemImage: "doc.viewfinder") { addFlow.isScanning = true }
        }
        Button("Choose Photos", systemImage: "photo.on.rectangle") { addFlow.isPickingPhotos = true }
        Button("Import PDFs and Files", systemImage: "folder") { addFlow.isPickingFiles = true }
        Button("Voice Note", systemImage: "mic") { addFlow.isRecordingNote = true }
    }

    private func item(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(Theme.accent)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "Voice" ? "Voice Note" : title)
    }
}

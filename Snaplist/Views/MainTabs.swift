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
        case home, library, spending, ask, add
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
                SpendingTab()
            }
            SwiftUI.Tab("Ask", systemImage: "sparkle.magnifyingglass", value: Tab.ask) {
                AskView(question: askQuestion, showsDone: false)
                    .id(askToken)
            }
            // The search role puts it in its own circle beside the tab bar:
            // the round + of the design.
            SwiftUI.Tab("Add", systemImage: "plus", value: Tab.add, role: .search) {
                AddView()
            }
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
        .fileImporter(isPresented: $addFlow.isPickingFiles, allowedContentTypes: [.pdf, .image, .commaSeparatedText],
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
        .sensoryFeedback(.success, trigger: model.records.count) { old, new in new > old && old > 0 }
        // From Siri, when the lock meant the answer had to be shown here.
        .task(id: model.pendingQuestion) {
            guard let question = model.pendingQuestion else { return }
            model.pendingQuestion = nil
            isShowingSettings = false
            ask(question)
        }
        // From a widget.
        .task(id: model.pendingLink) {
            guard let link = model.pendingLink else { return }
            model.pendingLink = nil
            isShowingSettings = false
            switch link {
            case .scan:
                if addFlow.canScan { addFlow.isScanning = true } else { selection = .add }
            case .ask: selection = .ask
            case .spending: selection = .spending
            case .home: selection = .home
            case .library:
                libraryPath = []
                selection = .library
            case .recap:
                selection = .home
                model.showRecap = true
            }
        }
        .modifier(ProPaywall())
        // From the Control Center control or the Action button.
        .onReceive(NotificationCenter.default.publisher(for: LinkRequests.notification)) { _ in
            if let link = LinkRequests.take() { model.pendingLink = link }
        }
        .onAppear {
            if let link = LinkRequests.take() { model.pendingLink = link }
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

/// The + tab: every way to add something, as big buttons.
private struct AddView: View {
    @Environment(AddFlow.self) private var addFlow
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if addFlow.canScan {
                        option("Scan a document", "Paper receipts, bills and letters, with the camera.", "doc.viewfinder") {
                            addFlow.isScanning = true
                        }
                    }
                    option("Choose photos", "Pictures of receipts or of where you put things.", "photo.on.rectangle") {
                        addFlow.isPickingPhotos = true
                    }
                    option("Import PDFs and files", "Statements and bills you downloaded, or a card's CSV export.", "folder") {
                        addFlow.isPickingFiles = true
                    }
                    option("Record a voice note", "Say where something is; it becomes searchable.", "mic") {
                        addFlow.isRecordingNote = true
                    }
                    Label("You can also share a PDF to Snaplist from Mail, Files or Safari.", systemImage: "square.and.arrow.up")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Add")
        }
    }

    /// Free is full: the paywall instead of the camera or a picker.
    private func canAdd() -> Bool {
        model.records.count < Pro.freeRecordLimit || Pro.shared.require(.records)
    }

    private func option(_ title: String, _ detail: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: { if canAdd() { action() } }) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.display(.headline))
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Spending with Pro; what it would show without.
private struct SpendingTab: View {
    var body: some View {
        if Pro.shared.isUnlocked {
            OverviewView(showsDone: false)
        } else {
            NavigationStack {
                ProLocked(feature: .spending) { EmptyView() }
                    .navigationTitle("Spending")
            }
        }
    }
}

/// The paywall, wherever Pro is asked for, and the App Store check at launch.
private struct ProPaywall: ViewModifier {
    func body(content: Content) -> some View {
        content
            .paywallSheet()
            .task { await Pro.shared.start() }
    }
}

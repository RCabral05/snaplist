import ArchiveCore
import PhotosUI
import SwiftUI
import VisionKit

/// Home: everything saved, newest first, and a search field over all of it.
struct RecordListView: View {
    @Environment(AppModel.self) private var model

    @State private var isScanning = false
    @State private var isPickingPhotos = false
    @State private var isPickingFiles = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var pendingDelete: Record?
    @State private var isShowingSettings = false

    /// Where a row leads: the record, and for a search hit the page that matched.
    struct Destination: Hashable {
        var record: Record
        var pagePosition: Int?
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                if model.query.isEmpty {
                    ForEach(model.visibleRecords) { record in
                        NavigationLink(value: Destination(record: record)) {
                            RecordRow(record: record)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = record }
                        }
                        .contextMenu { rowActions(record) }
                    }
                } else {
                    ForEach(model.hits) { hit in
                        NavigationLink(value: Destination(record: hit.record, pagePosition: hit.pagePosition)) {
                            SearchHitRow(hit: hit)
                        }
                        .contextMenu { rowActions(hit.record) }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if !model.records.isEmpty { KindFilterBar() }
            }
            .overlay { emptyState }
            .navigationTitle("Snaplist")
            .searchable(text: $model.query, prompt: "Search everything you've saved")
            .navigationDestination(for: Destination.self) { destination in
                RecordDetailView(record: destination.record, focusPage: destination.pagePosition)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                }
                ToolbarItem(placement: .primaryAction) { addMenu }
            }
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .fullScreenCover(isPresented: $isScanning) {
                DocumentScanner { images in
                    isScanning = false
                    model.importScan(images)
                } onCancel: {
                    isScanning = false
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $isPickingPhotos, selection: $photoSelection,
                          maxSelectionCount: 20, matching: .images)
            .onChange(of: photoSelection) { _, items in
                guard !items.isEmpty else { return }
                photoSelection = []
                Task { await model.importPhotos(items) }
            }
            .fileImporter(isPresented: $isPickingFiles, allowedContentTypes: [.pdf, .image],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): model.importFiles(urls)
                case .failure(let error): model.errorMessage = error.localizedDescription
                }
            }
            .confirmationDialog("Delete this record?", isPresented: isConfirmingDelete, titleVisibility: .visible,
                                presenting: pendingDelete) { record in
                Button("Delete \"\(record.title)\"", role: .destructive) { model.delete(record.id) }
            } message: { _ in
                Text("The original and its text are removed from this iPhone. This can't be undone.")
            }
            .alert("Something went wrong", isPresented: hasError) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    /// Long-press on a row: recategorise or delete without opening it.
    @ViewBuilder private func rowActions(_ record: Record) -> some View {
        CategoryMenu(record: record)
        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = record }
    }

    private var addMenu: some View {
        Menu {
            // False on the simulator and on devices without a camera.
            if VNDocumentCameraViewController.isSupported {
                Button("Scan Document", systemImage: "doc.viewfinder") { isScanning = true }
            }
            Button("Choose Photos", systemImage: "photo.on.rectangle") { isPickingPhotos = true }
            Button("Import Files", systemImage: "folder") { isPickingFiles = true }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !model.query.isEmpty && model.hits.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else if model.query.isEmpty && !model.records.isEmpty && model.visibleRecords.isEmpty,
                  let kind = model.kindFilter {
            ContentUnavailableView("No \(kind.pluralLabel.lowercased())", systemImage: kind.symbol,
                                   description: Text("Nothing is filed under \(kind.pluralLabel) right now."))
        } else if model.query.isEmpty && model.records.isEmpty {
            ContentUnavailableView {
                Label("Nothing saved yet", systemImage: "tray")
            } description: {
                Text("Scan a receipt, or add photos and PDFs. Everything stays on this iPhone, and the text in it becomes searchable.")
            } actions: {
                addMenu.buttonStyle(.borderedProminent)
            }
        }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var hasError: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

struct RecordRow: View {
    let record: Record

    var body: some View {
        HStack(spacing: 12) {
            RecordThumbnail(record: record)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title).lineLimit(1)
                HStack(spacing: 6) {
                    Label(record.kind.label, systemImage: record.kind.symbol)
                        .labelStyle(.titleOnly)
                    Text("·")
                    Text(record.createdAt, format: .dateTime.month().day().year())
                    IngestBadge(status: record.status)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct SearchHitRow: View {
    let hit: SearchHit

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The page that matched, not just the first one.
            RecordThumbnail(record: hit.record, pagePosition: hit.pagePosition)
            VStack(alignment: .leading, spacing: 4) {
                Text(hit.record.title)
                    .lineLimit(1)
                Text(snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if hit.matchingPages > 1 {
                    Text("Matches on \(hit.matchingPages) pages")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var snippet: AttributedString {
        hit.snippet.runs.reduce(into: AttributedString()) { result, run in
            var part = AttributedString(run.text)
            if run.isMatch {
                part.font = .subheadline.bold()
                part.foregroundColor = .primary
            }
            result += part
        }
    }
}

struct IngestBadge: View {
    let status: IngestStatus

    var body: some View {
        switch status {
        case .pending:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Reading text…")
            }
        case .failed:
            Label("Couldn't read text", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .ready:
            EmptyView()
        }
    }
}

extension RecordKind {
    var label: String {
        switch self {
        case .receipt: "Receipt"
        case .statement: "Statement"
        case .bill: "Bill"
        case .warranty: "Warranty"
        case .manual: "Manual"
        case .document: "Document"
        case .item: "Item"
        case .other: "Other"
        }
    }

    var pluralLabel: String {
        switch self {
        case .receipt: "Receipts"
        case .statement: "Statements"
        case .bill: "Bills"
        case .warranty: "Warranties"
        case .manual: "Manuals"
        case .document: "Documents"
        case .item: "Items"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .receipt: "receipt"
        case .statement: "list.bullet.rectangle"
        case .bill: "envelope"
        case .warranty: "checkmark.shield"
        case .manual: "book.closed"
        case .document: "doc.text"
        case .item: "shippingbox"
        case .other: "square.dashed"
        }
    }
}

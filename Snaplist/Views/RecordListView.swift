import ArchiveCore
import PhotosUI
import SwiftUI
import VisionKit

/// Home: everything saved as a grid of previews grouped by date, category
/// filters above it, and search over all of it.
struct RecordListView: View {
    @Environment(AppModel.self) private var model

    @State private var isScanning = false
    @State private var isPickingPhotos = false
    @State private var isPickingFiles = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var pendingDelete: Record?
    @State private var isShowingSettings = false

    /// Where a card leads: the record, and for a search hit the page that matched.
    struct Destination: Hashable {
        var record: Record
        var pagePosition: Int?
    }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ScrollView {
                if model.records.isEmpty {
                    WelcomeView(canScan: canScan, scan: { isScanning = true },
                                choosePhotos: { isPickingPhotos = true }, importFiles: { isPickingFiles = true })
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        KindFilterBar()
                        if model.query.isEmpty {
                            grid
                        } else {
                            searchResults
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Snaplist")
            .navigationSubtitle(subtitle)
            // Hidden on the welcome screen, where it would cover the buttons
            // and has nothing to search yet.
            .searchable(when: !model.records.isEmpty, text: $model.query, prompt: "Stores, amounts, any word")
            .navigationDestination(for: Destination.self) { destination in
                RecordDetailView(record: destination.record, focusPage: destination.pagePosition)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) { addMenu }
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
            .sensoryFeedback(.success, trigger: model.records.count) { old, new in new > old }
        }
    }

    // MARK: Grid

    @ViewBuilder private var grid: some View {
        let groups = DateGroup.grouping(model.visibleRecords)
        if groups.isEmpty, let kind = model.kindFilter {
            ContentUnavailableView("No \(kind.pluralLabel.lowercased())", systemImage: kind.symbol,
                                   description: Text("Nothing is filed under \(kind.pluralLabel) right now."))
                .padding(.top, 40)
        }
        LazyVStack(alignment: .leading, spacing: 28) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    Text(group.title)
                        .font(Theme.display(.title3))
                        .padding(.horizontal, 4)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(group.records) { record in
                            NavigationLink(value: Destination(record: record)) {
                                RecordCard(record: record)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { rowActions(record) }
                            .accessibilityIdentifier("record")
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: Search

    @ViewBuilder private var searchResults: some View {
        if model.hits.isEmpty {
            ContentUnavailableView.search(text: model.query)
                .padding(.top, 40)
        } else {
            LazyVStack(spacing: 10) {
                Text(model.hits.count == 1 ? "1 match" : "\(model.hits.count) matches")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                ForEach(model.hits) { hit in
                    NavigationLink(value: Destination(record: hit.record, pagePosition: hit.pagePosition)) {
                        SearchHitCard(hit: hit)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { rowActions(hit.record) }
                    .accessibilityIdentifier("record")
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: Actions

    /// Long-press on a card: recategorise or delete without opening it.
    @ViewBuilder private func rowActions(_ record: Record) -> some View {
        CategoryMenu(record: record)
        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = record }
    }

    /// False on the simulator and on devices without a camera.
    private var canScan: Bool { VNDocumentCameraViewController.isSupported }

    private var addMenu: some View {
        Menu {
            if canScan {
                Button("Scan Document", systemImage: "doc.viewfinder") { isScanning = true }
            }
            Button("Choose Photos", systemImage: "photo.on.rectangle") { isPickingPhotos = true }
            Button("Import Files", systemImage: "folder") { isPickingFiles = true }
        } label: {
            Label("Add", systemImage: "plus")
        } primaryAction: {
            if canScan { isScanning = true } else { isPickingPhotos = true }
        }
        .buttonStyle(.glassProminent)
        .accessibilityHint("Tap to scan, or hold for photos and files")
    }

    private var subtitle: String {
        let count = model.records.count
        guard count > 0 else { return "" }
        let reading = model.records.count { $0.status == .pending }
        let base = count == 1 ? "1 document" : "\(count) documents"
        return reading > 0 ? "\(base) · reading \(reading)" : base
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var hasError: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

/// A grid cell: the preview, then the name and where it's filed.
struct RecordCard: View {
    let record: Record

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RecordThumbnail(record: record, style: .card)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                .overlay(alignment: .topLeading) {
                    StatusPill(status: record.status).padding(8)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    Circle().fill(record.kind.tint).frame(width: 7, height: 7)
                    Text(record.kind.label)
                    Text("·")
                    Text(record.createdAt, format: .dateTime.month(.abbreviated).day())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A search result: the page that matched, and the words around the match.
struct SearchHitCard: View {
    let hit: SearchHit

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RecordThumbnail(record: hit.record, pagePosition: hit.pagePosition, style: .square(64))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(hit.record.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(hit.record.createdAt, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(snippet)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    KindBadge(kind: hit.record.kind)
                    if hit.matchingPages > 1 {
                        Text("\(hit.matchingPages) pages match")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .contentShape(Rectangle())
    }

    private var snippet: AttributedString {
        hit.snippet.runs.reduce(into: AttributedString()) { result, run in
            var part = AttributedString(run.text)
            if run.isMatch {
                part.font = .footnote.bold()
                part.foregroundColor = .primary
                part.backgroundColor = .yellow.opacity(0.35)
            }
            result += part
        }
    }
}

/// "Reading…" or "Couldn't read" over a preview; nothing once it's ready.
struct StatusPill: View {
    let status: IngestStatus

    var body: some View {
        switch status {
        case .pending:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Reading")
            }
            .pill()
        case .failed:
            Label("Couldn't read", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .pill()
        case .ready:
            EmptyView()
        }
    }
}

private extension View {
    @ViewBuilder
    func searchable(when enabled: Bool, text: Binding<String>, prompt: String) -> some View {
        if enabled {
            searchable(text: text, prompt: Text(prompt))
        } else {
            self
        }
    }

    func pill() -> some View {
        font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: .capsule)
    }
}

/// Longer form of the status, for the record detail header.
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

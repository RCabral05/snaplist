import ArchiveCore
import PDFKit
import SwiftUI

/// One record: its pages to swipe through (tap for full screen), what it is
/// and where it came from, and the text read from the page on screen.
struct RecordDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// As it was when the card was tapped; `current` follows later changes.
    let record: Record
    /// The page a search hit points at, shown first.
    let focusPage: Int?

    @State private var slots: [PageSlot] = []
    @State private var assets: [Asset] = []
    @State private var selection = 0
    @State private var zoomed: PageSlot?
    @State private var isEditing = false
    @State private var redacted: RedactedCopy.Result?
    @State private var isConfirmingDelete = false
    @State private var isShowingAllText = false
    @State private var copied = false
    @State private var transactions: [Amount] = []
    /// A printed amount being pointed at: its page and line.
    @State private var focusedLine: (page: Int, line: Int)?
    /// Changes on every "Show on Page", even for the same line twice.
    @State private var focusToken = 0

    /// One swipeable page. Before the text is read there are no `Page` rows
    /// yet, so a slot can also be just an original's first page.
    struct PageSlot: Identifiable {
        var index: Int
        var asset: Asset
        var pageInAsset: Int
        var page: Page?
        var lines: [TextLine]
        var id: Int { index }
    }

    /// Picks up changes made elsewhere, e.g. text finishing while this is open.
    private var current: Record {
        model.records.first { $0.id == record.id } ?? record
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    pager.id("pager")
                    header
                    statusBanner
                    details
                    TagsSection(record: current)
                    // Things owned: not statements, bills, IDs or screenshots.
                    if [.receipt, .warranty, .manual, .item, .other].contains(current.kind) {
                        ThingsSection(record: current)
                    }
                    AmountsSection(record: current, transactions: transactions, showOnPage: showOnPage)
                    DuplicatesSection(record: current)
                    if current.kind == .statement {
                        StatementCheckSection(record: current)
                    }
                    textSection
                }
                .padding(.bottom, 32)
            }
            .onChange(of: focusToken) {
                withAnimation(.snappy) { proxy.scrollTo("pager", anchor: .top) }
            }
        }
        .background(Theme.background)
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !assets.isEmpty {
                    Menu {
                        ShareLink(items: assets.map { model.archive.url(for: $0) }) {
                            Label("Share Original", systemImage: "doc")
                        }
                        if assets.contains(where: { $0.type == .image || $0.type == .pdf }) {
                            Button("Share with Private Details Hidden", systemImage: "eye.slash") {
                                do {
                                    redacted = try RedactedCopy.make(current, archive: model.archive)
                                } catch {
                                    model.errorMessage = "Couldn't make the copy: \(error.localizedDescription)"
                                }
                            }
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                Menu {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                    CategoryMenu(record: current)
                    CollectionMenu(record: current)
                    if current.status == .failed {
                        Button("Read Text Again", systemImage: "arrow.clockwise") { model.retry(current.id) }
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .confirmationDialog("Delete \"\(current.title)\"?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        model.delete(current.id)
                        dismiss()
                    }
                } message: {
                    Text("The original and its text are removed from this iPhone. This can't be undone.")
                }
            }
        }
        .sheet(isPresented: $isEditing) { EditRecordView(record: current) }
        .sheet(item: $redacted) { copy in RedactedPreview(copy: copy) }
        .fullScreenCover(item: $zoomed) { slot in
            ZoomViewer(url: model.archive.url(for: slot.asset), type: slot.asset.type,
                       pageInAsset: slot.pageInAsset, title: current.title)
        }
        .task(id: "\(current.status)-\(current.kind)-\(model.amountsRevision)") { load() }
    }

    // MARK: Pages

    @ViewBuilder private var pager: some View {
        if slots.isEmpty {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(.quaternary)
                .frame(height: 440)
                .overlay(ProgressView())
                .padding(.horizontal)
        } else {
            VStack(spacing: 10) {
                TabView(selection: $selection) {
                    ForEach(slots) { slot in
                        Group {
                            if slot.asset.type == .audio {
                                AudioNoteCard(url: model.archive.url(for: slot.asset), transcript: slot.page?.text)
                            } else {
                                PageImageView(url: model.archive.url(for: slot.asset), type: slot.asset.type,
                                              pageInAsset: slot.pageInAsset, highlights: highlights(on: slot))
                                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                                    .contentShape(Rectangle())
                                    .onTapGesture { zoomed = slot }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityHint("Opens the page full screen")
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .frame(maxHeight: .infinity)
                        .tag(slot.index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 460)

                if slots.count > 1 {
                    PageDots(count: slots.count, selection: selection)
                }
            }
        }
    }

    // MARK: About

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            KindBadge(kind: current.kind)
            Text(current.title)
                .font(Theme.display(.title, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if let day = current.documentDate {
                    Text("\(day.date().formatted(date: .long, time: .omitted)) · added \(current.createdAt.formatted(date: .abbreviated, time: .omitted))")
                } else {
                    Text("Added \(current.createdAt.formatted(date: .long, time: .shortened))")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder private var statusBanner: some View {
        switch current.status {
        case .pending:
            Label {
                Text("Reading the text on this record. It'll be searchable in a moment.")
            } icon: {
                ProgressView()
            }
            .font(.subheadline)
            .card()
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                Label("Couldn't read the text", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                if let reason = current.failureReason {
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Try Again") { model.retry(current.id) }
                    .buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        case .ready:
            EmptyView()
        }
    }

    private var details: some View {
        VStack(spacing: 0) {
            detailRow("Category") {
                Picker("Category", selection: kindBinding) {
                    ForEach(RecordKind.allCases, id: \.self) { kind in
                        Label(kind.label, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .tint(current.kind.tint)
                .labelsHidden()
            }
            Divider().padding(.leading)
            detailRow("Pages") { Text("\(max(slots.count, assets.count))") }
            Divider().padding(.leading)
            detailRow("Text") { Text(textSource) }
            Divider().padding(.leading)
            detailRow("Size") {
                Text(assets.reduce(Int64(0)) { $0 + $1.byteSize }.formatted(.byteCount(style: .file)))
            }
        }
        .font(.subheadline)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .padding(.horizontal)
    }

    private var kindBinding: Binding<RecordKind> {
        Binding(get: { current.kind }, set: { model.setKind($0, for: current) })
    }

    private func detailRow<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            value()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var textSource: String {
        let sources = Set(slots.compactMap(\.page?.textSource))
        if sources == [.speech] { return "Transcribed on this iPhone" }
        if sources == [.file] { return "From the bank's file" }
        switch (sources.contains(.ocr), sources.contains(.pdfText)) {
        case (true, true): return "PDF and read on iPhone"
        case (true, false): return "Read on this iPhone"
        case (false, true): return "From the PDF"
        case (false, false): return current.status == .pending ? "Reading…" : "None"
        }
    }

    // MARK: Text

    @ViewBuilder private var textSection: some View {
        if let slot = slots.first(where: { $0.index == selection }), let page = slot.page {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(slots.count > 1 ? "Text on page \(slot.index + 1)" : "Text")
                        .font(Theme.display(.title3))
                    Spacer()
                    Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = page.text
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    }
                    .font(.subheadline)
                    .disabled(page.text.isEmpty)
                    .sensoryFeedback(.success, trigger: copied) { _, new in new }
                }

                Text(page.text.isEmpty ? "No text found on this page." : page.text)
                    .font(.footnote.monospaced())
                    .foregroundStyle(page.text.isEmpty ? .secondary : .primary)
                    .lineLimit(isShowingAllText ? nil : 8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))

                HStack {
                    if page.textSource != .pdfText && page.textSource != .file {
                        Label(page.textSource == .speech ? "Transcribed automatically; may contain mistakes."
                                                         : "Read automatically; may contain mistakes.",
                              systemImage: page.textSource == .speech ? "waveform" : "text.viewfinder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if page.text.split(whereSeparator: \.isNewline).count > 8 {
                        Button(isShowingAllText ? "Show Less" : "Show All") {
                            withAnimation(.snappy) { isShowingAllText.toggle() }
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: Loading

    private var searchTerms: [String] {
        model.query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Lines containing a search term, and the row of an amount being
    /// pointed at. A PDF's text layer has no positions yet, so its lines are
    /// found but not drawn.
    private func highlights(on slot: PageSlot) -> [PageRect] {
        var boxes = searchTerms.isEmpty ? [] : slot.lines.compactMap { line in
            searchTerms.contains { line.text.localizedStandardContains($0) } ? line.box : nil
        }
        if let focusedLine, focusedLine.page == slot.index,
           let anchor = slot.lines.first(where: { $0.position == focusedLine.line })?.box {
            // Everything on the same printed row: OCR splits "TOTAL" and "72.65".
            let mid = anchor.y + anchor.height / 2
            boxes += slot.lines.compactMap(\.box).filter { abs(($0.y + $0.height / 2) - mid) < anchor.height * 0.6 }
        }
        return boxes
    }

    private func showOnPage(_ transaction: Amount) {
        guard let page = transaction.pagePosition else { return }
        withAnimation(.snappy) {
            selection = page
            focusedLine = transaction.linePosition.map { (page, $0) }
        }
        focusToken += 1
    }

    private func load() {
        do {
            let store = model.archive.store
            assets = try store.assets(of: record.id)
            let byId = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
            let pages = try store.pages(of: record.id)

            if pages.isEmpty {
                slots = assets.enumerated().map { index, asset in
                    PageSlot(index: index, asset: asset, pageInAsset: 0, page: nil, lines: [])
                }
            } else {
                slots = try pages.compactMap { page in
                    guard let id = page.id, let asset = byId[page.assetId] else { return nil }
                    return PageSlot(index: page.position, asset: asset, pageInAsset: page.pageInAsset,
                                    page: page, lines: try store.lines(of: id))
                }
            }
            if let focusPage, slots.contains(where: { $0.index == focusPage }) {
                selection = focusPage
            }
            transactions = try store.transactions(of: record.id)
        } catch {
            model.errorMessage = "Couldn't load this record: \(error.localizedDescription)"
        }
    }
}

/// Small dots under the pager; the current page's is wider.
private struct PageDots: View {
    let count: Int
    let selection: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == selection ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: index == selection ? 18 : 7, height: 7)
            }
        }
        .animation(.snappy, value: selection)
        .accessibilityElement()
        .accessibilityLabel("Page \(selection + 1) of \(count)")
    }
}

private extension View {
    func card() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .padding(.horizontal)
    }
}

/// The copy with private details hidden, to check before sending.
private struct RedactedPreview: View {
    @Environment(\.dismiss) private var dismiss
    let copy: RedactedCopy.Result

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PDFPreview(url: copy.url)
                VStack(alignment: .leading, spacing: 6) {
                    Label(copy.hidden == 0 ? "Nothing private found to hide."
                          : copy.hidden == 1 ? "1 line hidden." : "\(copy.hidden) lines hidden.",
                          systemImage: "eye.slash")
                        .font(.subheadline.weight(.medium))
                    Text(copy.missed > 0
                         ? "\(copy.missed) more couldn't be placed on the page. Check the copy before sending, and use the original markup tools if something still shows."
                         : "Card and account numbers, addresses, phone numbers and ID numbers are covered. Check the copy before sending.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Theme.surface)
            }
            .navigationTitle("Private Details Hidden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: copy.url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
        }
    }
}

private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}

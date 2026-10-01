import ArchiveCore
import SwiftUI

/// One record: every page of every original, with the words being searched
/// for highlighted where they were found, and the text read from each page.
struct RecordDetailView: View {
    @Environment(AppModel.self) private var model

    /// As it was when the row was tapped; `current` follows later changes.
    let record: Record
    /// The page a search hit points at, scrolled to on open.
    let focusPage: Int?

    @State private var pages: [LoadedPage] = []
    @State private var assets: [Asset] = []

    struct LoadedPage: Identifiable {
        var page: Page
        var asset: Asset
        var lines: [TextLine]
        var id: Int { page.position }
    }

    /// Picks up status changes, e.g. text finishing while this screen is open.
    private var current: Record {
        model.records.first { $0.id == record.id } ?? record
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    header
                    if pages.isEmpty {
                        // Not read yet, or unreadable: the originals are still worth seeing.
                        ForEach(assets) { asset in
                            PageImageView(url: model.archive.url(for: asset), type: asset.type, pageInAsset: 0)
                        }
                    } else {
                        ForEach(pages) { loaded in
                            PageCard(loaded: loaded, pageCount: pages.count, url: model.archive.url(for: loaded.asset),
                                     terms: searchTerms)
                                .id(loaded.page.position)
                        }
                    }
                }
                .padding()
            }
            .task(id: current.status) {
                load()
                if let focusPage, !pages.isEmpty {
                    proxy.scrollTo(focusPage, anchor: .top)
                }
            }
        }
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(current.kind.label, systemImage: current.kind.symbol)
                Spacer()
                Text(current.createdAt, format: .dateTime.month().day().year().hour().minute())
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            switch current.status {
            case .pending:
                IngestBadge(status: .pending).font(.subheadline)
            case .failed:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Couldn't read the text in this record", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    if let reason = current.failureReason {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Try Again") { model.retry(current.id) }
                        .buttonStyle(.bordered)
                }
                .font(.subheadline)
            case .ready:
                EmptyView()
            }
        }
    }

    private var searchTerms: [String] {
        model.query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private func load() {
        do {
            let store = model.archive.store
            assets = try store.assets(of: record.id)
            let byId = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
            pages = try store.pages(of: record.id).compactMap { page in
                guard let id = page.id, let asset = byId[page.assetId] else { return nil }
                return LoadedPage(page: page, asset: asset, lines: try store.lines(of: id))
            }
        } catch {
            model.errorMessage = "Couldn't load this record: \(error.localizedDescription)"
        }
    }
}

private struct PageCard: View {
    let loaded: RecordDetailView.LoadedPage
    let pageCount: Int
    let url: URL
    let terms: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageImageView(url: url, type: loaded.asset.type, pageInAsset: loaded.page.pageInAsset,
                          highlights: highlights)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)

            DisclosureGroup("Text on this page") {
                Text(loaded.page.text.isEmpty ? "No text found." : loaded.page.text)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .font(.subheadline)
        }
    }

    private var caption: String {
        let source = switch loaded.page.textSource {
        case .ocr: "Text read from the image; it may contain mistakes."
        case .pdfText: "Text from the PDF itself."
        }
        return pageCount > 1 ? "Page \(loaded.page.position + 1) of \(pageCount). \(source)" : source
    }

    /// Lines containing any search term. PDF text-layer lines have no position
    /// yet, so they are found but not highlighted.
    private var highlights: [PageRect] {
        guard !terms.isEmpty else { return [] }
        return loaded.lines.compactMap { line in
            terms.contains { line.text.localizedStandardContains($0) } ? line.box : nil
        }
    }
}

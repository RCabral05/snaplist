import ArchiveCore
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The archive as the screens see it: the record list, the current search,
/// and the ways in. Imports save the originals at once and read their text in
/// the background, so the record appears immediately and becomes searchable a
/// moment later.
@MainActor @Observable
final class AppModel {
    let archive: Archive
    private let ingestor: Ingestor

    private(set) var records: [Record] = []
    private(set) var hits: [SearchHit] = []
    var query = "" {
        didSet { search() }
    }
    /// The category chip that's selected; nil is "All". Applies to search too.
    var kindFilter: RecordKind? {
        didSet { search() }
    }
    var errorMessage: String?
    /// Each receipt's and bill's total, for its card.
    private(set) var totals: [UUID: Money] = [:]
    /// Bumped when amounts change, which the record list doesn't observe.
    private(set) var amountsRevision = 0

    private let thumbnails = NSCache<NSString, UIImage>()

    struct KindCount {
        var kind: RecordKind
        var count: Int
    }

    var visibleRecords: [Record] {
        guard let kindFilter else { return records }
        return records.filter { $0.kind == kindFilter }
    }

    /// Categories in use, in the enum's order. The selected one stays even at
    /// zero, so moving the last record out of it doesn't strand the filter.
    var kindCounts: [KindCount] {
        RecordKind.allCases.compactMap { kind in
            let count = records.count { $0.kind == kind }
            return count > 0 || kind == kindFilter ? KindCount(kind: kind, count: count) : nil
        }
    }

    init(archive: Archive) {
        self.archive = archive
        self.ingestor = Ingestor(archive: archive, extractor: VisionTextExtractor())
    }

    /// The archive lives in Application Support, inside the app's sandbox.
    static func live() throws -> AppModel {
        var name = "Archive"
        #if DEBUG
        // Screenshots run against a throwaway archive, never the real one.
        if DemoData.isEnabled {
            name = "DemoArchive"
            try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: name))
        }
        #endif
        let directory = URL.applicationSupportDirectory.appending(path: name, directoryHint: .isDirectory)
        return AppModel(archive: try Archive.open(at: directory))
    }

    /// Runs for the life of the window.
    func start() async {
        if let ids = try? archive.store.records().map(\.id) {
            _ = try? archive.files.sweep(keeping: Set(ids), unchangedSince: .now.addingTimeInterval(-3600))
        }
        #if DEBUG
        if DemoData.shouldSeed, (try? archive.store.records().isEmpty) ?? false {
            DemoData.seed(into: self)
        }
        #endif
        // Names records read before naming existed, e.g. "Scan Sep 30…".
        _ = try? archive.store.refreshSuggestions()
        resumePending()

        do {
            for try await list in archive.store.recordUpdates() {
                records = list
                refreshTotals()
                // A record that just became ready may now match.
                search()
            }
        } catch {
            errorMessage = "The record list stopped updating: \(error.localizedDescription)"
        }
    }

    /// Picks up imports interrupted by the app closing or the phone locking.
    func resumePending() {
        let ingestor = ingestor
        Task { await ingestor.processPending() }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            hits = []
            return
        }
        do {
            hits = try archive.store.search(text, kind: kindFilter)
        } catch {
            hits = []
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }

    // MARK: Adding

    func importScan(_ images: [UIImage]) {
        let items = images
            .compactMap { $0.jpegData(compressionQuality: 0.85) }
            .map { ImportItem(type: .image, source: .data($0), fileExtension: "jpg") }
        guard !items.isEmpty else { return }
        add(title: "Scan · \(Date.now.formatted(.dateTime.month(.abbreviated).day()))", nameSource: .automatic, items: items)
    }

    /// One record per photo: picking five receipts means five receipts.
    func importPhotos(_ selection: [PhotosPickerItem]) async {
        for item in selection {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                add(title: "Photo · \(Date.now.formatted(.dateTime.month(.abbreviated).day()))", nameSource: .automatic,
                    items: [ImportItem(type: .image, source: .data(data), fileExtension: ext)])
            } catch {
                errorMessage = "Couldn't load a photo: \(error.localizedDescription)"
            }
        }
    }

    /// A voice note becomes an item named by what was said.
    func importVoiceNote(_ url: URL) {
        add(kind: .item, title: "Voice note · \(Date.now.formatted(.dateTime.month(.abbreviated).day()))",
            nameSource: .automatic, items: [ImportItem(type: .audio, source: .file(url), fileExtension: "m4a")])
        try? FileManager.default.removeItem(at: url)
    }

    /// Camera-roll and scanner names say nothing: "IMG_4021", "Scan 3",
    /// "Document", a UUID. Those get a name read from the text instead.
    static func isGenericFileName(_ name: String) -> Bool {
        let lower = name.lowercased()
        let letters = lower.filter(\.isLetter)
        let generic = ["img", "image", "photo", "scan", "scanned", "document", "doc", "untitled", "file", "pxl", "dsc"]
        return letters.count < 3 || generic.contains { lower.hasPrefix($0) } || UUID(uuidString: name) != nil
    }

    /// One record per file, named after the file.
    func importFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) ?? false
            let name = url.deletingPathExtension().lastPathComponent
            add(title: name, nameSource: Self.isGenericFileName(name) ? .automatic : .file,
                items: [ImportItem(type: isPDF ? .pdf : .image, source: .file(url), fileExtension: url.pathExtension)])
        }
    }

    /// Imports start as a plain document; the person files them afterwards.
    func add(kind: RecordKind = .document, title: String, nameSource: NameSource = .person,
             items: [ImportItem], at date: Date = .now) {
        do {
            let record = try archive.add(kind: kind, title: title, nameSource: nameSource, items: items, at: date)
            let ingestor = ingestor
            Task { await ingestor.process(record.id) }
        } catch {
            errorMessage = "Couldn't save that: \(error.localizedDescription)"
        }
    }

    // MARK: Amounts

    func transactions(of recordId: UUID) -> [Amount] {
        (try? archive.store.transactions(of: recordId)) ?? []
    }

    func save(_ transaction: Amount) {
        do {
            try archive.store.save(transaction)
            amountsChanged()
        } catch {
            errorMessage = "Couldn't save the amount: \(error.localizedDescription)"
        }
    }

    func deleteTransaction(_ id: Int64, of recordId: UUID) {
        do {
            try archive.store.delete(transaction: id, of: recordId)
            amountsChanged()
        } catch {
            errorMessage = "Couldn't delete the amount: \(error.localizedDescription)"
        }
    }

    func setDocumentDate(_ day: Day, for recordId: UUID) {
        do {
            try archive.store.setDocumentDate(day, for: recordId)
        } catch {
            errorMessage = "Couldn't save the date: \(error.localizedDescription)"
        }
    }

    private func amountsChanged() {
        amountsRevision += 1
        refreshTotals()
    }

    private func refreshTotals() {
        totals = (try? archive.store.recordTotals()) ?? [:]
    }

    // MARK: Asking

    /// Answered from the archive by ArchiveCore: rules to read the question,
    /// SQL and integer sums for the numbers.
    func ask(_ text: String) -> AskResult {
        let today = Day(.now)
        do {
            switch QuestionParser.parse(text, today: today) {
            case .spending(let query):
                return .spending(try archive.store.answer(query))
            case .whereIs(let terms):
                return .whereIs(try archive.store.whereIs(terms), terms: terms)
            case .expiry(let terms):
                return .expiry(try archive.store.expiries(terms), terms: terms)
            case .search(let text):
                return .search(try archive.store.search(text, limit: 10), text: text)
            }
        } catch {
            errorMessage = "Couldn't answer that: \(error.localizedDescription)"
            return .search([], text: text)
        }
    }

    /// A spending question re-asked with a different period, from an answer's
    /// "other months" buttons.
    func answer(_ query: SpendingQuery) -> AskResult {
        do {
            return .spending(try archive.store.answer(query))
        } catch {
            errorMessage = "Couldn't answer that: \(error.localizedDescription)"
            return .spending(SpendingAnswer(query: query, totals: [], counted: [], duplicates: [], notes: []))
        }
    }

    // MARK: Changing

    /// Refiling can change a record's amounts, so totals refresh too.
    func update(_ record: Record) {
        do {
            try archive.store.update(record)
            amountsChanged()
        } catch {
            errorMessage = "Couldn't save the change: \(error.localizedDescription)"
        }
    }

    func setKind(_ kind: RecordKind, for record: Record) {
        var updated = record
        updated.kind = kind
        update(updated)
    }

    /// A small preview of a page, decoded off the main actor and kept in
    /// memory. Originals never change, so a cached preview never goes stale.
    func thumbnail(for recordId: UUID, pagePosition: Int?, maxPixelSize: Int = 240) async -> UIImage? {
        let key = "\(recordId.uuidString)#\(pagePosition ?? 0)@\(maxPixelSize)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let source = thumbnailSource(recordId, pagePosition: pagePosition) else { return nil }

        let image = await PageImages.load(archive.url(for: source.asset), type: source.asset.type,
                                          pageInAsset: source.pageInAsset, maxPixelSize: maxPixelSize)
        if let image { thumbnails.setObject(image, forKey: key) }
        return image
    }

    /// The page at `pagePosition` once text has been read; before that (or
    /// with no position) the first page of the first original.
    private func thumbnailSource(_ recordId: UUID, pagePosition: Int?) -> (asset: Asset, pageInAsset: Int)? {
        guard let assets = try? archive.store.assets(of: recordId), let first = assets.first else { return nil }
        if let pagePosition,
           let page = try? archive.store.pages(of: recordId).first(where: { $0.position == pagePosition }),
           let asset = assets.first(where: { $0.id == page.assetId }) {
            return (asset, page.pageInAsset)
        }
        return (first, 0)
    }

    func retry(_ recordId: UUID) {
        do {
            try archive.store.markPending(recordId)
            let ingestor = ingestor
            Task { await ingestor.process(recordId) }
        } catch {
            errorMessage = "Couldn't retry: \(error.localizedDescription)"
        }
    }

    func delete(_ recordId: UUID) {
        do {
            try archive.delete(recordId)
        } catch {
            errorMessage = "Couldn't delete that: \(error.localizedDescription)"
        }
    }
}

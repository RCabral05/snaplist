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
        if DemoData.isEnabled, (try? archive.store.records().isEmpty) ?? false {
            DemoData.seed(into: self)
        }
        #endif
        resumePending()

        do {
            for try await list in archive.store.recordUpdates() {
                records = list
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
        add(title: "Scan \(Date.now.formatted(date: .abbreviated, time: .shortened))", items: items)
    }

    /// One record per photo: picking five receipts means five receipts.
    func importPhotos(_ selection: [PhotosPickerItem]) async {
        for item in selection {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                add(title: "Photo \(Date.now.formatted(date: .abbreviated, time: .shortened))",
                    items: [ImportItem(type: .image, source: .data(data), fileExtension: ext)])
            } catch {
                errorMessage = "Couldn't load a photo: \(error.localizedDescription)"
            }
        }
    }

    /// One record per file, named after the file.
    func importFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) ?? false
            add(title: url.deletingPathExtension().lastPathComponent,
                items: [ImportItem(type: isPDF ? .pdf : .image, source: .file(url), fileExtension: url.pathExtension)])
        }
    }

    /// Imports start as a plain document; the person files them afterwards.
    func add(kind: RecordKind = .document, title: String, items: [ImportItem], at date: Date = .now) {
        do {
            let record = try archive.add(kind: kind, title: title, items: items, at: date)
            let ingestor = ingestor
            Task { await ingestor.process(record.id) }
        } catch {
            errorMessage = "Couldn't save that: \(error.localizedDescription)"
        }
    }

    // MARK: Changing

    func update(_ record: Record) {
        do {
            try archive.store.update(record)
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
    func thumbnail(for recordId: UUID, pagePosition: Int?) async -> UIImage? {
        let key = "\(recordId.uuidString)#\(pagePosition ?? 0)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let source = thumbnailSource(recordId, pagePosition: pagePosition) else { return nil }

        let image = await PageImages.load(archive.url(for: source.asset), type: source.asset.type,
                                          pageInAsset: source.pageInAsset, maxPixelSize: 240)
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

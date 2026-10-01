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
    var errorMessage: String?

    init(archive: Archive) {
        self.archive = archive
        self.ingestor = Ingestor(archive: archive, extractor: VisionTextExtractor())
    }

    /// The archive lives in Application Support, inside the app's sandbox.
    static func live() throws -> AppModel {
        let directory = URL.applicationSupportDirectory.appending(path: "Archive", directoryHint: .isDirectory)
        return AppModel(archive: try Archive.open(at: directory))
    }

    /// Runs for the life of the window.
    func start() async {
        if let ids = try? archive.store.records().map(\.id) {
            _ = try? archive.files.sweep(keeping: Set(ids), unchangedSince: .now.addingTimeInterval(-3600))
        }
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
            hits = try archive.store.search(text)
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

    /// Everything starts as a plain document until editing exists.
    private func add(title: String, items: [ImportItem]) {
        do {
            let record = try archive.add(kind: .document, title: title, items: items)
            let ingestor = ingestor
            Task { await ingestor.process(record.id) }
        } catch {
            errorMessage = "Couldn't save that: \(error.localizedDescription)"
        }
    }

    // MARK: Changing

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

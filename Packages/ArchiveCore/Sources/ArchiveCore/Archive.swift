import Foundation

/// The database and the originals together. Adding and deleting go through here
/// because both have to happen to both, in an order that fails safe.
public struct Archive: Sendable {
    public let store: ArchiveStore
    public let files: ArchiveFiles

    public init(store: ArchiveStore, files: ArchiveFiles) {
        self.store = store
        self.files = files
    }

    /// `directory/archive.sqlite` and `directory/Originals/`.
    public static func open(at directory: URL) throws -> Archive {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = try ArchiveFiles(root: directory.appendingPathComponent("Originals", isDirectory: true))
        let store = try ArchiveStore.open(at: directory.appendingPathComponent("archive.sqlite"))
        return Archive(store: store, files: files)
    }

    /// Saves the originals, then the rows. The record starts `pending`; an
    /// `Ingestor` reads its text afterwards. If the rows cannot be written the
    /// files are removed, so a failed import leaves nothing behind.
    @discardableResult
    public func add(kind: RecordKind, title: String, items: [ImportItem], at date: Date = Date()) throws -> Record {
        precondition(!items.isEmpty, "a record needs at least one original")
        let record = Record(kind: kind, title: title, createdAt: date)

        do {
            let assets = try items.enumerated().map { position, item in
                let assetId = UUID()
                let (fileName, size) = try files.save(item, recordId: record.id, assetId: assetId)
                return Asset(id: assetId, recordId: record.id, position: position,
                             type: item.type, fileName: fileName, byteSize: size)
            }
            try store.insert(record, assets: assets)
        } catch {
            try? files.removeRecord(record.id)
            throw error
        }
        return record
    }

    /// Rows first, then files. If the file removal fails the person no longer
    /// sees the record; the folder is an orphan `ArchiveFiles.sweep` collects.
    public func delete(_ recordId: UUID) throws {
        try store.delete(recordId)
        try files.removeRecord(recordId)
    }

    public func deleteEverything() throws {
        try store.deleteAll()
        try files.removeAll()
    }

    public func url(for asset: Asset) -> URL {
        files.url(for: asset)
    }
}

/// One original to import: a scanned page, a picked photo, a PDF.
public struct ImportItem: Sendable {
    public enum Source: Sendable {
        case data(Data)
        /// Copied, never moved: the picker's file belongs to someone else.
        case file(URL)
    }

    public var type: AssetType
    public var source: Source
    /// Lowercased and kept, so a HEIC stays a HEIC.
    public var fileExtension: String

    public init(type: AssetType, source: Source, fileExtension: String) {
        self.type = type
        self.source = source
        self.fileExtension = fileExtension.lowercased()
    }
}

import Foundation

/// The originals on disk: `root/<record id>/<asset id>.<ext>`. One folder per
/// record makes deleting a record one call, and a sweep can tell an orphan
/// folder by its name.
public struct ArchiveFiles: Sendable {
    public let root: URL

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.protect(root)
    }

    public func url(for asset: Asset) -> URL {
        root.appendingPathComponent(asset.fileName)
    }

    /// Returns the path relative to `root` and the size in bytes.
    func save(_ item: ImportItem, recordId: UUID, assetId: UUID) throws -> (String, Int64) {
        let folder = root.appendingPathComponent(recordId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let ext = item.fileExtension.isEmpty ? "" : ".\(item.fileExtension)"
        let fileName = "\(recordId.uuidString)/\(assetId.uuidString)\(ext)"
        let destination = root.appendingPathComponent(fileName)

        switch item.source {
        case .data(let data):
            try data.write(to: destination, options: .atomic)
        case .file(let url):
            try FileManager.default.copyItem(at: url, to: destination)
        }
        try Self.protect(destination)

        let size = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber
        return (fileName, size?.int64Value ?? 0)
    }

    public func removeRecord(_ recordId: UUID) throws {
        let folder = root.appendingPathComponent(recordId.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    public func removeAll() throws {
        for item in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: item)
        }
    }

    /// Removes folders whose record is gone. Returns how many it removed.
    /// Only folders untouched since `cutoff` count: an import writes its files
    /// before its rows, so a brand-new folder with no record yet is not an orphan.
    @discardableResult
    public func sweep(keeping recordIds: Set<UUID>, unchangedSince cutoff: Date) throws -> Int {
        var removed = 0
        for item in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: item.lastPathComponent), !recordIds.contains(id) else { continue }
            let modified = try FileManager.default.attributesOfItem(atPath: item.path)[.modificationDate] as? Date
            guard let modified, modified < cutoff else { continue }
            try FileManager.default.removeItem(at: item)
            removed += 1
        }
        return removed
    }

    /// Originals are unreadable while the phone is locked. The cost is that
    /// text extraction only runs while the app is open, which is when imports
    /// happen anyway. Nothing to do on platforms without Data Protection.
    private static func protect(_ url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
    }
}

import Foundation
import Testing
@testable import ArchiveCore

/// Returns canned pages per file extension, or throws for ".bad".
struct FakeExtractor: TextExtractor {
    var pagesByExtension: [String: [RecognizedPage]] = [:]

    struct Unreadable: Error, CustomStringConvertible {
        var description: String { "could not read file" }
    }

    func pages(of fileURL: URL, type: AssetType) async throws -> [RecognizedPage] {
        if fileURL.pathExtension == "bad" { throw Unreadable() }
        return pagesByExtension[fileURL.pathExtension] ?? []
    }
}

func page(_ lines: String..., source: TextSource = .ocr) -> RecognizedPage {
    RecognizedPage(
        lines: lines.enumerated().map { index, text in
            RecognizedLine(text: text, box: PageRect(x: 0.1, y: Double(index) * 0.05, width: 0.8, height: 0.04),
                           confidence: 0.9)
        },
        source: source)
}

final class TemporaryArchive {
    let directory: URL
    let archive: Archive

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveCoreTests-\(UUID().uuidString)", isDirectory: true)
        archive = try Archive.open(at: directory)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func folderCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: archive.files.root.path).count
    }
}

let jpeg = ImportItem(type: .image, source: .data(Data([0xFF, 0xD8, 0xFF])), fileExtension: "JPG")

@Suite struct AddingAndIngesting {
    @Test func addSavesTheOriginalAndStartsPending() throws {
        let tmp = try TemporaryArchive()
        let record = try tmp.archive.add(kind: .receipt, title: "Shell", items: [jpeg])

        #expect(try tmp.archive.store.record(record.id)?.status == .pending)
        let assets = try tmp.archive.store.assets(of: record.id)
        #expect(assets.count == 1)
        #expect(assets[0].fileName.hasSuffix(".jpg"))
        #expect(assets[0].byteSize == 3)
        #expect(try Data(contentsOf: tmp.archive.url(for: assets[0])) == Data([0xFF, 0xD8, 0xFF]))
        #expect(try tmp.archive.store.pendingRecordIds() == [record.id])
    }

    @Test func importingAFileCopiesItAndLeavesTheSource() throws {
        let tmp = try TemporaryArchive()
        let source = tmp.directory.appendingPathComponent("statement.pdf")
        try Data("%PDF".utf8).write(to: source)

        let record = try tmp.archive.add(kind: .statement, title: "Visa",
                                         items: [ImportItem(type: .pdf, source: .file(source), fileExtension: "pdf")])

        #expect(FileManager.default.fileExists(atPath: source.path))
        let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
        #expect(try Data(contentsOf: tmp.archive.url(for: asset)) == Data("%PDF".utf8))
    }

    @Test func aFailedImportLeavesNoFiles() throws {
        let tmp = try TemporaryArchive()
        let missing = ImportItem(type: .pdf, source: .file(tmp.directory.appendingPathComponent("nope.pdf")),
                                 fileExtension: "pdf")
        #expect(throws: (any Error).self) {
            try tmp.archive.add(kind: .document, title: "x", items: [jpeg, missing])
        }
        #expect(try tmp.folderCount() == 0)
        #expect(try tmp.archive.store.records().isEmpty)
    }

    @Test func ingestingStoresPagesLinesAndMarksReady() async throws {
        let tmp = try TemporaryArchive()
        let pdf = ImportItem(type: .pdf, source: .data(Data()), fileExtension: "pdf")
        let record = try tmp.archive.add(kind: .statement, title: "Visa September", items: [jpeg, pdf])
        let extractor = FakeExtractor(pagesByExtension: [
            "jpg": [page("Cover letter")],
            "pdf": [page("Page one", source: .pdfText), page("Page two", "SHELL OIL 57.20", source: .pdfText)],
        ])

        await Ingestor(archive: tmp.archive, extractor: extractor).processPending()

        #expect(try tmp.archive.store.record(record.id)?.status == .ready)
        let pages = try tmp.archive.store.pages(of: record.id)
        #expect(pages.map(\.position) == [0, 1, 2])
        #expect(pages.map(\.pageInAsset) == [0, 0, 1])
        #expect(pages[2].text == "Page two\nSHELL OIL 57.20")
        #expect(pages[2].textSource == .pdfText)

        let lines = try tmp.archive.store.lines(of: try #require(pages[2].id))
        #expect(lines.map(\.text) == ["Page two", "SHELL OIL 57.20"])
        #expect(lines[1].box == PageRect(x: 0.1, y: 0.05, width: 0.8, height: 0.04))
        #expect(try tmp.archive.store.pendingRecordIds().isEmpty)
    }

    @Test func ingestingTwiceReplacesRatherThanDuplicates() async throws {
        let tmp = try TemporaryArchive()
        let record = try tmp.archive.add(kind: .receipt, title: "r", items: [jpeg])
        let ingestor = Ingestor(archive: tmp.archive, extractor: FakeExtractor(pagesByExtension: ["jpg": [page("hello")]]))

        await ingestor.process(record.id)
        await ingestor.process(record.id)

        #expect(try tmp.archive.store.pages(of: record.id).count == 1)
        #expect(try tmp.archive.store.search("hello").count == 1)
    }

    @Test func anUnreadableFileMarksTheRecordFailedAndKeepsIt() async throws {
        let tmp = try TemporaryArchive()
        let bad = ImportItem(type: .image, source: .data(Data([1])), fileExtension: "bad")
        let record = try tmp.archive.add(kind: .receipt, title: "Smudged", items: [bad])

        await Ingestor(archive: tmp.archive, extractor: FakeExtractor()).process(record.id)

        let stored = try #require(try tmp.archive.store.record(record.id))
        #expect(stored.status == .failed)
        #expect(stored.failureReason == "could not read file")
        #expect(try tmp.archive.store.pendingRecordIds().isEmpty)

        try tmp.archive.store.markPending(record.id)
        #expect(try tmp.archive.store.pendingRecordIds() == [record.id])
    }

    @Test func aRecordDeletedMidwayIsNotResurrected() throws {
        let tmp = try TemporaryArchive()
        let record = try tmp.archive.add(kind: .receipt, title: "r", items: [jpeg])
        let assetId = try #require(try tmp.archive.store.assets(of: record.id).first).id
        try tmp.archive.delete(record.id)

        try tmp.archive.store.saveText([ExtractedAsset(assetId: assetId, pages: [page("late")])], for: record.id)

        #expect(try tmp.archive.store.records().isEmpty)
        #expect(try tmp.archive.store.search("late").isEmpty)
    }

    @Test func recordUpdatesFollowChanges() async throws {
        let tmp = try TemporaryArchive()
        var updates = tmp.archive.store.recordUpdates().makeAsyncIterator()

        let initial = try await updates.next()
        #expect(initial == [])
        let record = try tmp.archive.add(kind: .receipt, title: "new", items: [jpeg])
        let afterAdd = try await updates.next()
        #expect(afterAdd?.map(\.id) == [record.id])
    }

    @Test func recordsAreNewestFirstAndFilterByKind() throws {
        let tmp = try TemporaryArchive()
        let old = try tmp.archive.add(kind: .receipt, title: "old", items: [jpeg], at: Date(timeIntervalSince1970: 1))
        let new = try tmp.archive.add(kind: .warranty, title: "new", items: [jpeg], at: Date(timeIntervalSince1970: 2))

        #expect(try tmp.archive.store.records().map(\.id) == [new.id, old.id])
        #expect(try tmp.archive.store.records(kind: .receipt).map(\.id) == [old.id])
    }
}

@Suite struct Searching {
    /// One ready record per (title, pages).
    func archive(_ records: [(String, [RecognizedPage])]) async throws -> TemporaryArchive {
        let tmp = try TemporaryArchive()
        for (title, pages) in records {
            let item = ImportItem(type: .image, source: .data(Data()), fileExtension: UUID().uuidString)
            let record = try tmp.archive.add(kind: .document, title: title, items: [item])
            let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
            try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: pages)], for: record.id)
        }
        return tmp
    }

    @Test func findsTextAndHighlightsIt() async throws {
        let tmp = try await archive([("Receipt", [page("SHELL OIL 12345", "Unleaded 10.2 gal", "Total 41.37")])])

        let hits = try tmp.archive.store.search("unleaded")
        #expect(hits.count == 1)
        #expect(hits[0].snippet.runs.contains(.init(text: "Unleaded", isMatch: true)))
        #expect(!hits[0].snippet.text.contains("\u{1}"))
    }

    @Test func wordsArePrefixesAndAllMustMatch() async throws {
        let tmp = try await archive([
            ("Samsung TV warranty", [page("Coverage: 2 years from purchase")]),
            ("Dishwasher warranty", [page("Coverage: 1 year")]),
        ])

        #expect(try tmp.archive.store.search("warrant").count == 2)
        #expect(try tmp.archive.store.search("warrant tv").map(\.record.title) == ["Samsung TV warranty"])
        #expect(try tmp.archive.store.search("warranty fridge").isEmpty)
    }

    @Test func caseAndAccentsDoNotMatter() async throws {
        let tmp = try await archive([("Café receipt", [page("CRÈME BRÛLÉE 8.00")])])
        #expect(try tmp.archive.store.search("creme brulee").count == 1)
        #expect(try tmp.archive.store.search("cafe").count == 1)
    }

    @Test func amountsAndPunctuationSearchAsTyped() async throws {
        let tmp = try await archive([("Phone bill", [page("AT&T Wireless", "Amount due $84.12")])])

        #expect(try tmp.archive.store.search("84.12").count == 1)
        #expect(try tmp.archive.store.search("$84.12").count == 1)
        #expect(try tmp.archive.store.search("84.13").isEmpty)
        #expect(try tmp.archive.store.search("AT&T").count == 1)
    }

    @Test func inputThatIsNotAQueryIsHarmless() async throws {
        let tmp = try await archive([("Note", [page("he said \"hi\" OR NOT")])])

        #expect(try tmp.archive.store.search("").isEmpty)
        #expect(try tmp.archive.store.search("  $ -- ").isEmpty)
        #expect(try tmp.archive.store.search("\"hi").count == 1)
        #expect(try tmp.archive.store.search("NOT").count == 1)
        #expect(try tmp.archive.store.search("hi*)(").count == 1)
    }

    @Test func oneHitPerRecordLandingOnItsBestPage() async throws {
        let tmp = try await archive([
            ("Manual", [page("Contents"), page("HDMI port setup", "Use the HDMI cable"), page("Index", "Antenna 4, Bluetooth 7, HDMI 12, Power 2, Remote 9, Wi-Fi 15")]),
        ])

        let hits = try tmp.archive.store.search("hdmi")
        #expect(hits.count == 1)
        #expect(hits[0].matchingPages == 2)
        #expect(hits[0].pagePosition == 1)
    }

    @Test func titleMatchesCount() async throws {
        let tmp = try await archive([("Spare HDMI cable - hall closet", [page("")])])
        #expect(try tmp.archive.store.search("closet").count == 1)
    }

    @Test func renamingUpdatesTheIndex() async throws {
        let tmp = try await archive([("Untitled", [page("some text")])])
        var record = try #require(try tmp.archive.store.records().first)
        record.title = "Garage shelf"
        record.kind = .item
        try tmp.archive.store.update(record)

        #expect(try tmp.archive.store.search("garage").first?.record.kind == .item)
        #expect(try tmp.archive.store.search("untitled").isEmpty)
    }

    @Test func pendingRecordsAreNotSearchableYet() throws {
        let tmp = try TemporaryArchive()
        try tmp.archive.add(kind: .receipt, title: "Pending one", items: [jpeg])
        #expect(try tmp.archive.store.search("pending").isEmpty)
    }

    @Test func limitCountsRecordsNotPages() async throws {
        let many = (0..<5).map { i in ("Doc \(i)", [page("apple"), page("apple")]) }
        let tmp = try await archive(many)
        #expect(try tmp.archive.store.search("apple", limit: 3).count == 3)
    }
}

@Suite struct Deleting {
    @Test func deletingARecordRemovesRowsIndexAndFiles() async throws {
        let tmp = try TemporaryArchive()
        let keep = try tmp.archive.add(kind: .receipt, title: "keep", items: [jpeg])
        let gone = try tmp.archive.add(kind: .receipt, title: "gone", items: [jpeg])
        await Ingestor(archive: tmp.archive, extractor: FakeExtractor(pagesByExtension: ["jpg": [page("shared words")]]))
            .processPending()

        try tmp.archive.delete(gone.id)

        #expect(try tmp.archive.store.records().map(\.id) == [keep.id])
        #expect(try tmp.archive.store.pages(of: gone.id).isEmpty)
        #expect(try tmp.archive.store.search("shared").map(\.record.id) == [keep.id])
        #expect(try tmp.folderCount() == 1)
    }

    @Test func deleteEverythingLeavesAnEmptyWorkingArchive() async throws {
        let tmp = try TemporaryArchive()
        try tmp.archive.add(kind: .receipt, title: "a", items: [jpeg])
        await Ingestor(archive: tmp.archive, extractor: FakeExtractor(pagesByExtension: ["jpg": [page("words")]]))
            .processPending()

        try tmp.archive.deleteEverything()

        #expect(try tmp.archive.store.records().isEmpty)
        #expect(try tmp.archive.store.search("words").isEmpty)
        #expect(try tmp.folderCount() == 0)
        try tmp.archive.add(kind: .receipt, title: "after", items: [jpeg])
        #expect(try tmp.archive.store.records().count == 1)
    }

    @Test func sweepRemovesOnlyOrphanFolders() throws {
        let tmp = try TemporaryArchive()
        let record = try tmp.archive.add(kind: .receipt, title: "a", items: [jpeg])
        let orphan = tmp.archive.files.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)

        let removed = try tmp.archive.files.sweep(keeping: Set(try tmp.archive.store.records().map(\.id)))

        #expect(removed == 1)
        #expect(try tmp.folderCount() == 1)
        #expect(try tmp.archive.store.assets(of: record.id).count == 1)
    }
}

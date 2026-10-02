import Foundation
import Testing
@testable import ArchiveCore

private func add(_ tmp: TemporaryArchive, kind: RecordKind, title: String, lines: [String]) throws -> UUID {
    let record = try tmp.archive.add(kind: kind, title: title,
                                     items: [ImportItem(type: .pdf, source: .data(Data([1])), fileExtension: "pdf")])
    let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
    try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: [
        RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: .pdfText),
    ])], for: record.id)
    return record.id
}

@Suite struct Tagging {
    @Test func tagsAreSharedAndCleanedUp() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        let tv = try add(tmp, kind: .warranty, title: "TV warranty", lines: ["SAMSUNG", "LIMITED WARRANTY"])
        let blender = try add(tmp, kind: .warranty, title: "Blender warranty", lines: ["Vitamix", "Coverage: 2 years"])

        let mom = try store.addTag("Mom", kind: .person, to: tv)
        let again = try store.addTag(" mom ", kind: .person, to: blender)
        #expect(mom.id == again.id)
        #expect(try store.tags().map(\.name) == ["Mom"])
        // The same name can be a person and a place.
        try store.addTag("Mom", kind: .place, to: blender)
        #expect(try store.tags(of: blender).map(\.kind) == [.place, .person].sorted { $0.rawValue > $1.rawValue })

        let tagsByRecord = try store.tagsByRecord()
        #expect(tagsByRecord[tv]?.map(\.name) == ["Mom"])
        #expect(tagsByRecord[blender]?.count == 2)

        try store.removeTag(try #require(mom.id), from: tv)
        #expect(try store.tags().count == 2)
        try store.removeTag(try #require(mom.id), from: blender)
        #expect(try store.tags().map(\.kind) == [.place])
    }

    @Test func tagsAreSearchable() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        let receipt = try add(tmp, kind: .receipt, title: "Legal Sea Foods", lines: ["LEGAL SEA FOODS", "TOTAL $84.20"])
        #expect(try store.search("boston").isEmpty)
        try store.addTag("Boston", kind: .place, to: receipt)
        #expect(try store.search("boston").map(\.id) == [receipt])

        // Renaming keeps the tag in the index.
        var record = try #require(try store.record(receipt))
        record.title = "Dinner"
        try store.update(record)
        #expect(try store.search("boston").map(\.id) == [receipt])

        let tag = try #require(try store.tags().first?.id)
        try store.removeTag(tag, from: receipt)
        #expect(try store.search("boston").isEmpty)
    }

    @Test func questionsNamingTags() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        let tv = try add(tmp, kind: .warranty, title: "TV warranty", lines: ["SAMSUNG", "LIMITED WARRANTY"])
        let dinner = try add(tmp, kind: .receipt, title: "Legal Sea Foods", lines: ["LEGAL SEA FOODS", "TOTAL $84.20"])
        let parking = try add(tmp, kind: .receipt, title: "Parking", lines: ["SP+ PARKING", "TOTAL $30.00"])
        try store.addTag("Mom", kind: .person, to: tv)
        try store.addTag("Mom", kind: .person, to: dinner)
        try store.addTag("Boston", kind: .place, to: dinner)
        try store.addTag("Boston", kind: .place, to: parking)

        let moms = try #require(try store.taggedRecords(matching: "Mom’s warranties"))
        #expect(moms.kind == .warranty)
        #expect(moms.records.map(\.id) == [tv])

        let boston = try #require(try store.taggedRecords(matching: "receipts from the Boston trip"))
        #expect(Set(boston.records.map(\.id)) == [dinner, parking])
        #expect(try store.taggedRecords(matching: "mom in boston")?.records.map(\.id) == [dinner])
        #expect(try store.taggedRecords(matching: "momentum") == nil)
        // Only the tags and a category: the question is about them.
        #expect(try store.taggedRecords(matching: "show me Mom's warranties")?.otherWords == [])
        // Other words too: probably about something else, so a text search.
        #expect(try store.taggedRecords(matching: "boston cream pie recipe")?.otherWords == ["cream", "pie", "recipe"])
        #expect(try store.taggedRecords(matching: "where is my passport") == nil)
    }

    @Test func spendingQuestionsMatchTags() throws {
        let tmp = try TemporaryArchive()
        let store = tmp.archive.store
        let dinner = try add(tmp, kind: .receipt, title: "Legal Sea Foods", lines: ["LEGAL SEA FOODS", "TOTAL $84.20"])
        let parking = try add(tmp, kind: .receipt, title: "Parking", lines: ["SP+ PARKING", "TOTAL $30.00"])
        _ = try add(tmp, kind: .receipt, title: "Shell", lines: ["SHELL", "TOTAL $40.00"])
        try store.addTag("Boston", kind: .place, to: dinner)
        try store.addTag("Boston", kind: .place, to: parking)

        #expect(try store.unknownMerchantTerms(["boston"]).isEmpty)
        let answer = try store.answer(SpendingQuery(merchantTerms: ["boston"]))
        #expect(answer.totals == [Money(cents: 8420 + 3000)])
    }

    @Test func deletingEverythingRemovesTags() throws {
        let tmp = try TemporaryArchive()
        let receipt = try add(tmp, kind: .receipt, title: "Parking", lines: ["TOTAL $30.00"])
        try tmp.archive.store.addTag("Boston", kind: .place, to: receipt)
        try tmp.archive.deleteEverything()
        #expect(try tmp.archive.store.tags().isEmpty)
    }
}

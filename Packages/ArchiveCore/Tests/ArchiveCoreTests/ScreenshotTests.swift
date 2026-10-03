import Foundation
import Testing
@testable import ArchiveCore

/// A screenshot of a photo of a router label, as Vision reads it. Made-up
/// network details.
private let routerScreenshot = RecognizedPage(lines: [
    RecognizedLine(text: "AT&T", box: PageRect(x: 0.05, y: 0.01, width: 0.1, height: 0.02)),
    RecognizedLine(text: "6:21 PM", box: PageRect(x: 0.45, y: 0.01, width: 0.12, height: 0.02)),
    RecognizedLine(text: "61%", box: PageRect(x: 0.85, y: 0.01, width: 0.08, height: 0.02)),
    RecognizedLine(text: "Photos", box: PageRect(x: 0.05, y: 0.07, width: 0.15, height: 0.025)),
    RecognizedLine(text: "44 of 84", box: PageRect(x: 0.42, y: 0.07, width: 0.16, height: 0.025)),
    RecognizedLine(text: "Connect to Wi-Fi:", box: PageRect(x: 0.1, y: 0.40, width: 0.3, height: 0.02)),
    RecognizedLine(text: "Wi-Fi Name (2.4 GHz): Example-Home", box: PageRect(x: 0.1, y: 0.43, width: 0.6, height: 0.02)),
    RecognizedLine(text: "Wi-Fi Password: correct-horse-42", box: PageRect(x: 0.1, y: 0.46, width: 0.6, height: 0.02)),
    RecognizedLine(text: "Support: www.example.com/routersupport", box: PageRect(x: 0.5, y: 0.52, width: 0.4, height: 0.015)),
], source: .ocr)

@Suite struct Screenshots {
    @Test func wifiLabelsAreNamedForWhatTheyAre() {
        #expect(Suggester.suggest([routerScreenshot]).title == "Wi-Fi Network")
    }

    @Test func aScreenshotsStatusBarIsntItsName() {
        var page = routerScreenshot
        page.lines = page.lines.filter { !$0.text.contains("Wi-Fi") }
        page.lines.append(RecognizedLine(text: "BLUE BOTTLE COFFEE", box: PageRect(x: 0.1, y: 0.3, width: 0.6, height: 0.04)))
        #expect(Suggester.suggest([page]).title == "Blue Bottle Coffee")
        // Without a time in the top strip it's not a screenshot: AT&T stays.
        let bill = RecognizedPage(lines: [RecognizedLine(text: "AT&T", box: PageRect(x: 0.05, y: 0.01, width: 0.2, height: 0.04))],
                                  source: .ocr)
        #expect(Suggester.suggest([bill]).title == "AT&T")
    }

    @Test func askingInPlainWordsFindsIt() throws {
        let tmp = try TemporaryArchive()
        let record = try tmp.archive.add(kind: .document, title: "Photo", nameSource: .automatic,
                                         items: [ImportItem(type: .image, source: .data(Data([1])), fileExtension: "jpg")])
        let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
        try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: [routerScreenshot])], for: record.id)
        let store = tmp.archive.store

        #expect(try store.record(record.id)?.title == "Wi-Fi Network")
        #expect(try store.searchQuestion("What’s my wifi password").map(\.id) == [record.id])
        #expect(try store.searchQuestion("wifi").map(\.id) == [record.id])
        // Not every word is on the page: the closest pages still come back.
        #expect(try store.searchQuestion("router admin password").map(\.id) == [record.id])
        #expect(try store.searchQuestion("passport number").isEmpty)
    }

    @Test func aTirePressureLabel() throws {
        // How Vision reads a sideways sticker once it's turned the right way up. Made up values.
        let tmp = try TemporaryArchive()
        let record = try tmp.archive.add(kind: .document, title: "Photo", nameSource: .automatic,
                                         items: [ImportItem(type: .image, source: .data(Data([1])), fileExtension: "jpg")])
        let asset = try #require(try tmp.archive.store.assets(of: record.id).first)
        let lines = ["COLD TIRE PRESSURE", "SOLO RIDING", "DUAL RIDING", "kPa kgf/cm2 psi", "FRONT 250 2.50 36",
                     "REAR 290 2.90 42", "TIRE SIZE FRONT 120/70ZR17M/C (58W)", "TYPE BRIDGESTONE BATTLAX BT016F G"]
        try tmp.archive.store.saveText([ExtractedAsset(assetId: asset.id, pages: [
            RecognizedPage(lines: lines.map { RecognizedLine(text: $0) }, source: .ocr)])], for: record.id)
        let store = tmp.archive.store
        #expect(try store.record(record.id)?.title == "Cold Tire Pressure")
        #expect(try store.record(record.id)?.kind == .document)
        #expect(try store.transactions(of: record.id).isEmpty)

        let question = "What psi should my tires be"
        guard case .search = QuestionParser.parse(question, today: Day(year: 2026, month: 10, day: 3)!) else {
            Issue.record("not a search"); return
        }
        #expect(!QuestionParser.mentionsMoney(question))
        #expect(try store.searchQuestion(question).map(\.record.id) == [record.id])
        #expect(try store.searchQuestion("tire pressure").map(\.record.id) == [record.id])
    }

    @Test func moneyQuestionsAreMoneyQuestions() {
        for question in ["How much did I spend on tires", "what did the tires cost", "tire shop receipt", "what did I get at Discount Tire"] {
            #expect(QuestionParser.mentionsMoney(question), "\(question)")
        }
        for question in ["What psi should my tires be", "what's my wifi password", "when does my passport expire"] {
            #expect(!QuestionParser.mentionsMoney(question), "\(question)")
        }
    }
}

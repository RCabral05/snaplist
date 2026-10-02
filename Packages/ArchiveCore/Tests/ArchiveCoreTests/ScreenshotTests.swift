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
}

import XCTest

/// Walks the main screens with sample data and keeps a screenshot of each,
/// in light and dark. CI exports them from the result bundle; nothing here
/// asserts on looks.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testTour() throws {
        for suffix in ["light", "dark"] {
            let scheme = suffix == "dark" ? "-forceDark" : "-forceLight"

            let empty = XCUIApplication()
            empty.launchArguments = ["-demoEmpty", scheme]
            empty.launch()
            sleep(2)
            snap("00-welcome-\(suffix)")
            empty.terminate()

            let app = XCUIApplication()
            app.launchArguments = ["-demoData", scheme]
            app.launch()

            let firstRecord = app.descendants(matching: .any).matching(identifier: "record").firstMatch
            XCTAssertTrue(firstRecord.waitForExistence(timeout: 30), "no records appeared")
            waitWhile(app.staticTexts["Reading"], timeout: 60)
            sleep(1)
            snap("01-home-\(suffix)")
            app.swipeUp()
            sleep(1)
            snap("01b-home-scrolled-\(suffix)")
            app.swipeDown()
            app.swipeDown()

            firstRecord.tap()
            sleep(2)
            snap("02-detail-\(suffix)")
            app.swipeUp()
            sleep(1)
            snap("03-detail-scrolled-\(suffix)")
            app.swipeDown()
            sleep(1)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
            sleep(2)
            snap("05-zoom-\(suffix)")
            if app.buttons["Done"].exists { app.buttons["Done"].tap() }
            sleep(1)
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)

            let receipts = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Receipts'")).firstMatch
            if receipts.waitForExistence(timeout: 3) {
                receipts.tap()
                sleep(1)
                snap("06-filtered-\(suffix)")
                receipts.tap()
            }

            let search = app.searchFields.firstMatch
            if !search.waitForExistence(timeout: 3) { app.swipeDown() }
            if search.waitForExistence(timeout: 5) {
                search.tap()
                search.typeText("shell")
                sleep(2)
                snap("04-search-\(suffix)")
            }
            app.terminate()
        }
    }

    private func waitWhile(_ element: XCUIElement, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline { sleep(1) }
    }

    @MainActor
    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

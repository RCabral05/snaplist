import XCTest

/// Walks the main screens with sample data and keeps a screenshot of each.
/// CI exports them from the result bundle; nothing here asserts on looks.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testTour() throws {
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            XCUIDevice.shared.appearance = appearance
            let suffix = appearance == .dark ? "dark" : "light"
            let app = XCUIApplication()
            app.launchArguments = ["-demoData"]
            app.launch()

            let firstRecord = app.descendants(matching: .any).matching(identifier: "record").firstMatch
            XCTAssertTrue(firstRecord.waitForExistence(timeout: 30), "no records appeared")
            waitWhile(app.staticTexts["Reading text…"], timeout: 60)
            snap("01-home-\(suffix)")

            firstRecord.tap()
            sleep(2)
            snap("02-detail-\(suffix)")
            app.swipeUp()
            sleep(1)
            snap("03-detail-scrolled-\(suffix)")
            app.navigationBars.buttons.firstMatch.tap()

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

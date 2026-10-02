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
        // Each theme, in light and dark where it has both. `-theme` lands in
        // UserDefaults, where the app reads the theme from.
        let looks: [(theme: String, scheme: String)] = [
            ("ledger", "light"), ("ledger", "dark"), ("vault", "dark"), ("clarity", "light"), ("clarity", "dark"),
        ]
        for look in looks {
            let suffix = "\(look.theme)-\(look.scheme)"
            let flags = ["-theme", look.theme, look.scheme == "dark" ? "-forceDark" : "-forceLight"]

            let empty = XCUIApplication()
            empty.launchArguments = ["-demoEmpty"] + flags
            empty.launch()
            sleep(2)
            snap("00-welcome-\(suffix)")
            empty.terminate()

            let app = XCUIApplication()
            app.launchArguments = ["-demoData"] + flags
            app.launch()

            XCTAssertTrue(app.textFields["home-ask"].waitForExistence(timeout: 30), "home didn't appear")
            waitWhile(app.staticTexts["Reading"], timeout: 60)
            sleep(3)
            snap("01-home-\(suffix)")
            app.swipeUp()
            sleep(1)
            snap("01b-home-scrolled-\(suffix)")

            tab(app, "Library")
            let firstRecord = app.descendants(matching: .any).matching(identifier: "record").firstMatch
            XCTAssertTrue(firstRecord.waitForExistence(timeout: 10), "no records appeared")
            sleep(1)
            snap("02-library-\(suffix)")

            let receipts = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Receipts'")).firstMatch
            if receipts.waitForExistence(timeout: 3) {
                receipts.tap()
                sleep(1)
                snap("03-filtered-\(suffix)")
                receipts.tap()
            }

            firstRecord.tap()
            sleep(2)
            snap("04-detail-\(suffix)")
            app.swipeUp()
            sleep(1)
            snap("05-detail-scrolled-\(suffix)")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)

            tab(app, "Spending")
            sleep(2)
            snap("06-spending-\(suffix)")

            tab(app, "Ask")
            sleep(1)
            snap("07-ask-\(suffix)")
            askQuestion(app, "How much did I spend on gas last month?")
            snap("08-ask-gas-\(suffix)")
            askQuestion(app, "Where did I put the spare HDMI cable?")
            snap("09-ask-where-\(suffix)")

            tab(app, "Library")
            let search = app.searchFields.firstMatch
            if !search.waitForExistence(timeout: 3) { app.swipeDown() }
            if search.waitForExistence(timeout: 5) {
                search.tap()
                search.typeText("shell")
                sleep(2)
                snap("10-search-\(suffix)")
            }
            app.terminate()
        }
    }

    @MainActor
    private func tab(_ app: XCUIApplication, _ name: String) {
        let button = app.tabBars.buttons[name]
        if button.waitForExistence(timeout: 3) {
            button.tap()
        } else {
            app.buttons[name].firstMatch.tap()
        }
        sleep(1)
    }

    @MainActor
    private func askQuestion(_ app: XCUIApplication, _ question: String) {
        let field = app.textFields["ask-field"].exists ? app.textFields["ask-field"] : app.textViews["ask-field"]
        guard field.waitForExistence(timeout: 3) else { return }
        field.tap()
        if let current = field.value as? String, !current.isEmpty, !current.hasPrefix("Ask about") {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(question)
        app.buttons["ask-button"].firstMatch.tap()
        sleep(2)
        app.swipeDown()
    }

    /// Done if it can be found, else swipe the sheet away: the toolbar
    /// button isn't always reachable once the keyboard has been up.
    @MainActor
    private func closeSheet(_ app: XCUIApplication) {
        let done = app.buttons.matching(NSPredicate(format: "label == 'Done'")).firstMatch
        if done.waitForExistence(timeout: 2), done.isHittable {
            done.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        sleep(1)
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

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

            let filter = app.buttons["library-filter"].firstMatch
            if filter.waitForExistence(timeout: 3) {
                filter.tap()
                let receipts = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Receipts'")).firstMatch
                if receipts.waitForExistence(timeout: 3) {
                    receipts.tap()
                    sleep(1)
                    snap("03-filtered-\(suffix)")
                    filter.tap()
                    app.buttons["Show All"].firstMatch.tap()
                }
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
            let search = app.textFields["library-search"].firstMatch
            if search.waitForExistence(timeout: 5) {
                search.tap()
                search.typeText("shell")
                sleep(2)
                snap("10-search-\(suffix)")
            }
            app.terminate()
        }
    }

    /// Every screen in one theme, for a full look at the app. Run with
    /// `-only-testing:SnaplistUITests/ScreenshotTests/testEveryScreen`.
    @MainActor
    func testEveryScreen() throws {
        let theme = ProcessInfo.processInfo.environment["TOUR_THEME"] ?? "vault"
        let flags = ["-theme", theme, theme == "clarity" ? "-forceLight" : "-forceDark"]
        var count = 0
        func shot(_ name: String) {
            count += 1
            snap(String(format: "%02d-%@", count, name))
        }

        let empty = XCUIApplication()
        empty.launchArguments = ["-demoEmpty"] + flags
        empty.launch()
        sleep(2)
        shot("welcome")
        empty.terminate()

        let app = XCUIApplication()
        app.launchArguments = ["-demoData"] + flags
        app.launch()
        XCTAssertTrue(app.textFields["home-ask"].waitForExistence(timeout: 30), "home didn't appear")
        waitWhile(app.staticTexts["Reading"], timeout: 60)
        sleep(3)

        // Home, top to bottom.
        shot("home")
        for index in 1...3 {
            app.swipeUp()
            sleep(1)
            shot("home-scrolled-\(index)")
        }
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        sleep(1)

        // The recap, a sheet.
        if open(app, "recap") {
            shot("recap")
            app.swipeUp(); sleep(1)
            shot("recap-scrolled")
            closeSheet(app)
        }

        // Each tool on Home.
        for (label, name) in [("IDs & policies", "ids"), ("Things", "things"), ("Tax report", "tax-report"),
                              ("Subscriptions", "subscriptions"), ("Car", "car")] {
            if open(app, label) {
                shot(name)
                app.swipeUp(); sleep(1)
                shot("\(name)-scrolled")
                back(app)
            }
        }
        if open(app, "Changes") { shot("changes"); back(app) }

        // Library, filters, a receipt, a statement.
        tab(app, "Library")
        let firstRecord = app.descendants(matching: .any).matching(identifier: "record").firstMatch
        if firstRecord.waitForExistence(timeout: 10) {
            sleep(1)
            shot("library")
            let filter = app.buttons["library-filter"].firstMatch
            if filter.waitForExistence(timeout: 3) {
                filter.tap(); sleep(1)
                shot("library-filter-menu")
                app.swipeDown(velocity: .fast)
                if app.buttons["library-filter"].exists == false { app.tap() }
            }
            for (term, name) in [("Shell", "receipt"), ("Chase", "statement")] {
                let search = app.textFields["library-search"].firstMatch
                guard search.waitForExistence(timeout: 3) else { break }
                search.tap()
                search.typeText(term + "\n")
                sleep(2)
                let record = app.descendants(matching: .any).matching(identifier: "record").firstMatch
                if record.waitForExistence(timeout: 3) {
                    record.tap(); sleep(2)
                    shot(name)
                    for index in 1...3 {
                        app.swipeUp(); sleep(1)
                        shot("\(name)-scrolled-\(index)")
                    }
                    back(app)
                }
                let clear = app.buttons["Clear text"].firstMatch
                if clear.exists { clear.tap() }
            }
        }

        // Spending.
        tab(app, "Spending")
        sleep(2)
        shot("spending")
        for index in 1...2 {
            app.swipeUp(); sleep(1)
            shot("spending-scrolled-\(index)")
        }

        // Ask.
        tab(app, "Ask")
        sleep(1)
        shot("ask")
        for (question, name) in [("How much did I spend on gas last month?", "ask-gas"),
                                 ("What did I buy at Costco?", "ask-items"),
                                 ("Where did I put the spare HDMI cable?", "ask-where"),
                                 ("When does my passport expire?", "ask-expiry")] {
            askQuestion(app, question)
            shot(name)
        }

        // Add.
        let add = app.buttons.matching(NSPredicate(format: "label == 'Add' OR identifier == 'add-tab'")).firstMatch
        if add.waitForExistence(timeout: 2) {
            add.tap(); sleep(2)
            shot("add")
            closeSheet(app)
        }

        // Settings and what's inside it.
        tab(app, "Home")
        app.swipeDown(velocity: .fast)
        let settings = app.buttons["Settings"].firstMatch
        if settings.waitForExistence(timeout: 3) {
            settings.tap(); sleep(2)
            shot("settings")
            for index in 1...3 {
                app.swipeUp(); sleep(1)
                shot("settings-scrolled-\(index)")
            }
            for (label, name) in [("Always Hide", "always-hide"), ("Apple Pay, Banks and Cards", "live-charges"), ("Theme", "themes")] {
                if open(app, label) {
                    shot(name)
                    back(app)
                }
            }
            app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
            if open(app, "Get Snaplist Pro") {
                sleep(2)
                shot("paywall")
                closeSheet(app)
            }
        }
        app.terminate()
    }

    /// Taps the first thing whose label starts with `label`, scrolling down
    /// to find it. False when it isn't there.
    @MainActor
    private func open(_ app: XCUIApplication, _ label: String) -> Bool {
        let predicate = NSPredicate(format: "label BEGINSWITH[c] %@", label)
        for _ in 0..<6 {
            for query in [app.buttons, app.staticTexts, app.cells] {
                let element = query.matching(predicate).firstMatch
                if element.exists, element.isHittable {
                    element.tap()
                    sleep(2)
                    return true
                }
            }
            app.swipeUp()
            sleep(1)
        }
        return false
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        if button.exists { button.tap() } else { app.swipeRight() }
        sleep(1)
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

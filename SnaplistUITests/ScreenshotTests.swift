import XCTest

/// Walks the main screens with sample data and keeps a screenshot of each,
/// in light and dark. CI exports them from the result bundle; nothing here
/// asserts on looks.
class ScreenshotTests: XCTestCase {
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

    /// Taps the first thing whose label starts with `label`, scrolling down
    /// to find it. False when it isn't there.
    @MainActor
    func open(_ app: XCUIApplication, _ label: String) -> Bool {
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
    func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        if button.exists { button.tap() } else { app.swipeRight() }
        sleep(1)
    }

    @MainActor
    func tab(_ app: XCUIApplication, _ name: String) {
        let button = app.tabBars.buttons[name]
        if button.waitForExistence(timeout: 3) {
            button.tap()
        } else {
            app.buttons[name].firstMatch.tap()
        }
        sleep(1)
    }

    @MainActor
    func askQuestion(_ app: XCUIApplication, _ question: String) {
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
    func closeSheet(_ app: XCUIApplication) {
        let done = app.buttons.matching(NSPredicate(format: "label == 'Done'")).firstMatch
        if done.waitForExistence(timeout: 2), done.isHittable {
            done.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        sleep(1)
    }

    func waitWhile(_ element: XCUIElement, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline { sleep(1) }
    }

    @MainActor
    func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Every screen in one theme (TOUR_THEME, Vault by default), a section per
/// test so one stuck screen doesn't lose the rest. Screenshots are named
/// section-number-screen.
final class EveryScreenTests: ScreenshotTests {
    private var section = ""
    private var count = 0

    @MainActor
    private func shot(_ name: String) {
        count += 1
        snap(String(format: "%@-%02d-%@", section, count, name))
    }

    @MainActor
    private func launch(_ section: String, empty: Bool = false) -> XCUIApplication {
        self.section = section
        count = 0
        let theme = ProcessInfo.processInfo.environment["TOUR_THEME"] ?? "vault"
        let app = XCUIApplication()
        app.launchArguments = [empty ? "-demoEmpty" : "-demoData", "-theme", theme,
                               theme == "clarity" ? "-forceLight" : "-forceDark"]
        app.launch()
        if empty {
            sleep(2)
        } else {
            XCTAssertTrue(app.textFields["home-ask"].waitForExistence(timeout: 30), "home didn't appear")
            waitWhile(app.staticTexts["Reading"], timeout: 60)
            sleep(3)
        }
        return app
    }

    @MainActor
    private func scrollShots(_ app: XCUIApplication, _ name: String, _ times: Int) {
        for index in 1...times {
            app.swipeUp()
            sleep(1)
            shot("\(name)-scrolled-\(index)")
        }
    }

    @MainActor
    func test1Home() {
        let empty = launch("1", empty: true)
        shot("welcome")
        empty.terminate()
        let app = launch("1")
        shot("home")
        scrollShots(app, "home", 3)
        app.terminate()
    }

    @MainActor
    func test2Tools() {
        let app = launch("2")
        if open(app, "Your ") {
            shot("recap")
            scrollShots(app, "recap", 2)
            closeSheet(app)
        }
        for (label, name) in [("IDs & policies", "ids"), ("Things", "things"), ("Tax report", "tax-report"),
                              ("Subscriptions", "subscriptions"), ("Car", "car")] {
            app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
            if open(app, label) {
                shot(name)
                scrollShots(app, name, 1)
                back(app)
            }
        }
        app.terminate()
    }

    @MainActor
    func test3Library() {
        let app = launch("3")
        tab(app, "Library")
        let firstRecord = app.descendants(matching: .any).matching(identifier: "record").firstMatch
        guard firstRecord.waitForExistence(timeout: 10) else { return }
        sleep(1)
        shot("library")
        scrollShots(app, "library", 1)
        app.swipeDown(velocity: .fast)
        let filter = app.buttons["library-filter"].firstMatch
        if filter.waitForExistence(timeout: 3) {
            filter.tap(); sleep(1)
            shot("filter-menu")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
            sleep(1)
        }
        for (term, name) in [("Shell", "receipt"), ("Chase Visa", "statement"), ("PG&E", "bill"), ("Samsung", "warranty")] {
            let search = app.textFields["library-search"].firstMatch
            guard search.waitForExistence(timeout: 3) else { break }
            search.tap()
            if let current = search.value as? String, !current.isEmpty, !current.hasPrefix("Search") {
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            search.typeText(term)
            sleep(2)
            if name == "receipt" { shot("search") }
            let record = app.descendants(matching: .any).matching(identifier: "record").firstMatch
            if record.waitForExistence(timeout: 3) {
                record.tap(); sleep(2)
                shot(name)
                scrollShots(app, name, 2)
                back(app)
            }
        }
        app.terminate()
    }

    @MainActor
    func test4Spending() {
        let app = launch("4")
        tab(app, "Spending")
        sleep(2)
        shot("spending")
        scrollShots(app, "spending", 3)
        app.terminate()
    }

    @MainActor
    func test5Ask() {
        let app = launch("5")
        tab(app, "Ask")
        sleep(1)
        shot("ask")
        for (question, name) in [("How much did I spend on gas last month?", "gas"),
                                 ("What did I buy at Costco?", "items"),
                                 ("How much did I spend on groceries this year?", "groceries"),
                                 ("Where did I put the spare HDMI cable?", "where"),
                                 ("When does my Samsung TV warranty expire?", "expiry")] {
            askQuestion(app, question)
            shot(name)
        }
        app.terminate()
    }

    @MainActor
    func test6Add() {
        let app = launch("6")
        let add = app.buttons.matching(NSPredicate(format: "label == 'Add' OR label == 'New' OR identifier == 'add-tab'")).firstMatch
        if add.waitForExistence(timeout: 3) {
            add.tap(); sleep(2)
            shot("add")
        }
        app.terminate()
    }

    @MainActor
    func test7Settings() {
        let app = launch("7")
        let settings = app.buttons["Settings"].firstMatch
        guard settings.waitForExistence(timeout: 3) else { return }
        settings.tap(); sleep(2)
        shot("settings")
        scrollShots(app, "settings", 4)
        for (label, name) in [("Always Hide", "always-hide"), ("Apple Pay, Banks and Cards", "live-charges"), ("Theme", "themes")] {
            for _ in 0..<5 { app.swipeDown(velocity: .fast) }
            if open(app, label) {
                shot(name)
                scrollShots(app, name, 1)
                back(app)
            }
        }
        for _ in 0..<5 { app.swipeDown(velocity: .fast) }
        if open(app, "Get Snaplist Pro") {
            sleep(3)
            shot("paywall")
            scrollShots(app, "paywall", 1)
        }
        app.terminate()
    }

    // The main tour isn't repeated here.
    @MainActor
    override func testTour() throws {}
}

import XCTest

@MainActor final class NavigationTests: XCTestCase {
    /// Holds the content button and picks a type from its menu.
    static func chooseMode(
        _ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let button = app.buttons["mode.button"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), file: file, line: line)
        button.press(forDuration: 0.8)
        let byID = app.buttons["mode.\(title.lowercased())"]
        var item = byID
        if !byID.waitForExistence(timeout: 2) {
            // Other controls can share the label; the menu's row is the hittable one on top.
            let rows = app.buttons.matching(NSPredicate(format: "label == %@", title))
            _ = rows.firstMatch.waitForExistence(timeout: 3)
            item = rows.allElementsBoundByIndex.last(where: \.isHittable) ?? rows.firstMatch
        }
        XCTAssertTrue(
            item.waitForExistence(timeout: 3), "Missing mode \(title)", file: file, line: line)
        item.tap()
        let chosen = NSPredicate(format: "value == %@", title)
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: chosen, object: button)], timeout: 3),
            .completed, "Content type should be \(title)", file: file, line: line)
    }

    func testContentButtonCyclesPicksAndPersists() {
        XCUIDevice.shared.orientation = .portrait
        // A fresh profile, so settings left by earlier runs can't change the layout.
        let app = XCUIApplication.fresh()
        app.launch()
        let mode = app.buttons["mode.button"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        XCTAssertEqual(mode.value as? String, "All")
        // A tap steps to the next content type.
        for title in ["Manga", "Novels", "Anime", "All"] {
            mode.tap()
            expectation(for: NSPredicate(format: "value == %@", title), evaluatedWith: mode)
            waitForExpectations(timeout: 3)
        }
        // Holding lists every type.
        Self.chooseMode("Manga", in: app)
        keepScreenshot("Content type chosen")
        app.openSettings()
        XCTAssertTrue(app.buttons["settings.category.Appearance"].waitForExistence(timeout: 3))
        // The type is app-wide: Settings › Library shows the same choice.
        app.openSettingsRow("settings.category.Library")
        XCTAssertTrue(
            app.buttons["settings.picker.Library mode"].shows("Manga"),
            app.buttons["settings.picker.Library mode"].label)
        app.terminate()
        // Same profile as the first launch: the chosen mode must survive a relaunch.
        app.launch()
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        XCTAssertEqual(mode.value as? String, "Manga")
        Self.chooseMode("All", in: app)
    }

    func testModeSurvivesLeavingAndReturningToLibrary() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication.fresh()
        app.launch()
        let library = app.buttons["tab.library"]
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.tap()
        Self.chooseMode("Novels", in: app)
        XCTAssertTrue(app.otherElements["page.library"].waitForExistence(timeout: 3))
        XCTAssertTrue(library.isSelected)
        app.openTab("home")
        XCTAssertFalse(library.isSelected)
        library.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.otherElements["page.library"].waitForExistence(timeout: 3))
        XCTAssertTrue(library.isSelected)
        XCTAssertEqual(app.buttons["mode.button"].value as? String, "Novels")
        Self.chooseMode("All", in: app)
    }

    /// Every type in the content menu can be picked with a tap.
    func testEveryContentTypeCanBeChosenFromTheMenu() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication.fresh()
        app.launch()
        for title in ["Manga", "Novels", "All"] {
            Self.chooseMode(title, in: app)
        }
        Self.chooseMode("Anime", in: app)
        keepScreenshot("Content menu after choosing Anime")
    }

    /// The Moku tab bar is custom: every control must stay on screen and keep a
    /// 44-point touch target in portrait and landscape.
    func testTabBarStaysInsideScreenInBothOrientations() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication.fresh()
        app.launch()
        XCTAssertTrue(app.buttons["tab.library"].waitForExistence(timeout: 10))
        for orientation: UIDeviceOrientation in [.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 0.8)
            app.openTab("library")
            let window = app.windows.firstMatch.frame
            for id in [
                "tab.home", "tab.browse", "tab.library", "tab.downloads", "tab.settings",
                "mode.button",
            ] {
                let button = app.buttons[id]
                XCTAssertTrue(button.isHittable, id)
                let frame = button.frame
                XCTAssertGreaterThanOrEqual(frame.width, 44, id)
                XCTAssertGreaterThanOrEqual(frame.height, 44, id)
                XCTAssertGreaterThanOrEqual(frame.minX, window.minX, id)
                XCTAssertLessThanOrEqual(frame.maxX, window.maxX, id)
                XCTAssertLessThanOrEqual(frame.maxY, window.maxY, id)
            }
            keepScreenshot("Tab bar \(orientation == .portrait ? "portrait" : "landscape")")
            app.openSettings()
            let item = app.buttons["more.category.History"]
            XCTAssertTrue(item.waitForExistence(timeout: 3))
            // Settings rows sit above the floating bar.
            XCTAssertLessThan(item.frame.maxY, app.buttons["tab.settings"].frame.minY)
            app.openTab("home")
            XCTAssertFalse(item.isHittable)
        }
    }
}

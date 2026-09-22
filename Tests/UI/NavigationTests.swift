import XCTest

@MainActor final class NavigationTests: XCTestCase {
    func testModesTabsAndSettingsNavigation() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let library = app.buttons["tab.library"]
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.tap()
        library.press(forDuration: 0.4)
        XCTAssertTrue(app.buttons["mode.all"].waitForExistence(timeout: 3))
        app.buttons["mode.manga"].tap()
        XCTAssertEqual(library.value as? String, "Manga")
        XCTAssertFalse(app.buttons["mode.anime"].exists)
        app.buttons["tab.home"].tap()
        XCTAssertFalse(app.buttons["header.profile"].exists)
        app.buttons.matching(identifier: "header.settings").allElementsBoundByIndex.first(
            where: \.isHittable)!.tap()
        XCTAssertTrue(app.buttons["settings.category.Appearance"].waitForExistence(timeout: 3))
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "phosphor-settings"
        capture.lifetime = .keepAlways
        add(capture)
        app.terminate()
        app.launch()
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        XCTAssertEqual(library.value as? String, "Manga")
        library.press(forDuration: 0.4)
        app.buttons["mode.all"].tap()
    }

    func testLibraryTapShowsSelectedModeAfterLeavingLibrary() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let library = app.buttons["tab.library"]
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.press(forDuration: 0.4)
        app.buttons["mode.anime"].tap()
        XCTAssertEqual(library.value as? String, "Anime")
        XCTAssertTrue(app.otherElements["library.page"].waitForExistence(timeout: 3))
        app.buttons["tab.home"].tap()
        library.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.otherElements["library.page"].waitForExistence(timeout: 3))
        XCTAssertEqual(library.value as? String, "Anime")
        XCTAssertFalse(app.buttons["mode.all"].exists)
        library.press(forDuration: 0.4)
        app.buttons["mode.all"].tap()
        XCTAssertEqual(library.value as? String, "All")
    }

    func testIslandsStayInsideScreenInBothOrientations() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab.library"].waitForExistence(timeout: 10))
        for orientation: UIDeviceOrientation in [.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let library = app.buttons["tab.library"]
            library.tap()
            library.press(forDuration: 0.8)
            XCTAssertTrue(app.buttons["mode.all"].waitForExistence(timeout: 3))
            let window = app.windows.firstMatch.frame
            for id in [
                "tab.home", "tab.library", "tab.browse", "tab.downloads", "tab.more", "mode.all",
                "mode.anime",
            ] {
                let button = app.buttons[id]
                XCTAssertTrue(button.isHittable, id)
                let frame = button.frame
                XCTAssertGreaterThanOrEqual(frame.width, 44, id)
                XCTAssertGreaterThanOrEqual(frame.height, 44, id)
                XCTAssertGreaterThanOrEqual(frame.minX, window.minX, id)
                XCTAssertLessThanOrEqual(frame.maxX, window.maxX, id)
                // The current floating bar deliberately extends into the bottom safe area.
                XCTAssertLessThanOrEqual(frame.maxY, window.maxY, id)
            }
            app.buttons["mode.all"].tap()
            app.buttons["tab.more"].tap()
            let item = app.buttons["moreMenu.Recent"]
            XCTAssertTrue(item.waitForExistence(timeout: 3))
            XCTAssertLessThan(item.frame.maxY, app.buttons["tab.more"].frame.minY)
            app.buttons["tab.home"].tap()
            XCTAssertFalse(item.exists)
        }
    }
}

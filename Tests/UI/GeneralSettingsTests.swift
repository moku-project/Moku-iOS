import XCTest

@MainActor final class GeneralSettingsUITests: XCTestCase {
    func testGeneralControlsPersistAndScaleRemainsNavigable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-profiles", "-mokuProfileTestID", UUID().uuidString, "--ui-testing-search",
        ]
        app.launch()
        openGeneral(app)
        let larger = app.buttons["settings.general.scale.125"]
        XCTAssertTrue(larger.waitForExistence(timeout: 4))
        larger.tap()
        XCTAssertTrue(app.buttons["settings.back"].isHittable)
        app.buttons["Reset interface scale"].tap()
        let timeout = app.buttons["settings.general.idleTimeout"]
        reveal(timeout, in: app)
        timeout.tap()
        app.buttons["Never"].tap()
        let language = app.textFields["settings.general.language"]
        reveal(language, in: app)
        language.tap()
        language.press(forDuration: 1)
        if app.menuItems["Select All"].waitForExistence(timeout: 1) {
            app.menuItems["Select All"].tap()
        }
        // Clear the current value through keyboard editing, without relying on a selection menu.
        let value = language.value as? String ?? "All"
        language.typeText(
            String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count) + "pt_BR\n")
        XCTAssertEqual(language.value as? String, "pt-br")
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "General desktop panels"
        capture.lifetime = .keepAlways
        add(capture)
        app.terminate()
        app.launch()
        openGeneral(app)
        reveal(timeout, in: app)
        XCTAssertEqual(timeout.value as? String, "Never")
        reveal(language, in: app)
        XCTAssertEqual(language.value as? String, "pt-br")
    }
    private func openGeneral(_ app: XCUIApplication) {
        let home = app.buttons["tab.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()
        let settings = app.buttons.matching(identifier: "header.settings").allElementsBoundByIndex
            .first(where: \.isHittable)
        XCTAssertNotNil(settings)
        settings?.tap()
        app.buttons["settings.category.General"].tap()
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable { app.scrollViews["settings.scroll"].swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}

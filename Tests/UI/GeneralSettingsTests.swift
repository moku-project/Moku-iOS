import XCTest

@MainActor final class GeneralSettingsUITests: XCTestCase {
    func testGeneralControlsPersistAndScaleRemainsNavigable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString, "--ui-testing-search",
        ]
        app.launch()
        openGeneral(app)
        let increase = app.buttons["settings.general.scale.increase"]
        XCTAssertTrue(increase.waitForExistence(timeout: 4))
        increase.tap()
        XCTAssertEqual(app.staticTexts["settings.general.scaleValue"].label, "105%")
        app.buttons["settings.general.scale.decrease"].tap()
        XCTAssertEqual(app.staticTexts["settings.general.scaleValue"].label, "100%")
        increase.tap()
        XCTAssertTrue(app.buttons["settings.back"].isHittable)
        app.buttons["Reset interface scale"].tap()
        XCTAssertEqual(app.staticTexts["settings.general.scaleValue"].label, "100%")
        let timeout = app.buttons["settings.general.idleTimeout"]
        reveal(timeout, in: app)
        timeout.tap()
        app.buttons["Never"].tap()
        let language = app.buttons["settings.general.language"]
        reveal(language, in: app)
        language.tap()
        let english = app.buttons["English"]
        for _ in 0..<6 where !english.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(english.isHittable)
        english.tap()
        XCTAssertEqual(language.value as? String, "English")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "General open sections"
        capture.lifetime = .keepAlways
        add(capture)
        app.terminate()
        app.launch()
        openGeneral(app)
        reveal(timeout, in: app)
        XCTAssertEqual(timeout.value as? String, "Never")
        reveal(language, in: app)
        XCTAssertEqual(language.value as? String, "English")
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

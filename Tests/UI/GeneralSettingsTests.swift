import XCTest

@MainActor final class GeneralSettingsUITests: XCTestCase {
    func testGeneralControlsPersistAndScaleRemainsNavigable() {
        let app = XCUIApplication.fresh(["--ui-testing-search"])
        app.launch()
        openGeneral(app)
        let scale = app.steppers["settings.general.scale"]
        XCTAssertTrue(scale.waitForExistence(timeout: 4))
        let value = app.staticTexts["settings.general.scaleValue"]
        app.buttons["settings.general.scale-Increment"].tap()
        XCTAssertTrue(value.label.hasSuffix("105%"), value.label)
        app.buttons["settings.general.scale-Decrement"].tap()
        XCTAssertTrue(value.label.hasSuffix("100%"), value.label)
        app.buttons["settings.general.scale-Increment"].tap()
        XCTAssertTrue(app.backButton.isHittable)
        app.buttons["Reset interface scale"].tap()
        XCTAssertTrue(value.label.hasSuffix("100%"), value.label)
        let form = app.collectionViews["settings.scroll"]
        let timeout = app.buttons["settings.general.idleTimeout"]
        app.reveal(timeout, in: form)
        timeout.tap()
        XCTAssertTrue(app.buttons["Never"].waitForExistence(timeout: 3))
        app.buttons["Never"].tap()
        XCTAssertTrue(timeout.shows("Never"), "\(timeout.label) \(String(describing: timeout.value))")
        // The language picker pushes a list of languages.
        let language = app.buttons["settings.general.language"]
        app.reveal(language, in: form)
        language.tap()
        let english = app.buttons["English"]
        XCTAssertTrue(english.waitForExistence(timeout: 3))
        for _ in 0..<6 where !english.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(english.isHittable)
        english.tap()
        if !language.waitForExistence(timeout: 2) { app.goBack() }
        app.reveal(language, in: form)
        XCTAssertTrue(language.shows("English"), "\(language.label) \(String(describing: language.value))")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        keepScreenshot("General settings")
        app.terminate()
        app.launch()
        openGeneral(app)
        app.reveal(timeout, in: form)
        XCTAssertTrue(timeout.shows("Never"), "\(timeout.label) \(String(describing: timeout.value))")
        app.reveal(language, in: form)
        XCTAssertTrue(language.shows("English"), "\(language.label) \(String(describing: language.value))")
    }

    private func openGeneral(_ app: XCUIApplication) {
        app.openSettings()
        app.openSettingsRow("settings.category.General")
        XCTAssertTrue(app.navigationBars["General"].waitForExistence(timeout: 5))
    }
}

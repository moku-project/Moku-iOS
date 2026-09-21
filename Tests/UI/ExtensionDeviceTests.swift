import XCTest

@MainActor final class ExtensionDeviceUITests: XCTestCase {
    func testSavedRepositoriesAndMangaDexAppear() throws {
        guard ProcessInfo.processInfo.environment["MOKU_LIVE_EXTENSION_CHECK"] == "1" else {
            throw XCTSkip("Opt-in check against the device's saved repositories.")
        }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab.more"].waitForExistence(timeout: 10))
        app.buttons["tab.more"].tap()
        app.buttons["more.category.Extensions"].tap()
        app.buttons["extensions.section"].tap()
        app.buttons["extensions.view.Repositories"].tap()
        XCTAssertTrue(app.staticTexts["Keiyoushi"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["Add your first repository"].exists)
        app.buttons["extensions.section"].tap()
        app.buttons["extensions.view.Installed"].tap()
        app.buttons["extensions.fab"].tap()
        app.buttons["extensions.action.Search"].tap()
        let query = app.textFields["extensions.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("MangaDex\n")
        app.buttons["Done"].tap()
        let source = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "MangaDex")
        ).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "extensions-device-recovered"
        capture.lifetime = .keepAlways
        add(capture)
    }
}

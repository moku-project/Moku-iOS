import XCTest

@MainActor final class UnifiedExtensionsTests: XCTestCase {
    func testInstalledSearchSettingsAndCatalogShareOnePage() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-extensions", "--ui-testing-search"]
        app.launch()
        app.buttons["tab.more"].tap()
        XCTAssertFalse(app.buttons["more.category.Sources"].exists)
        app.buttons["more.category.Extensions"].tap()
        let source = app.buttons["extensions.search.fixture"]
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        source.tap()
        // A source opens its own page: popular titles and a search inside the source.
        XCTAssertTrue(app.textFields["source.search"].waitForExistence(timeout: 5))
        app.textFields["source.search"].tap()
        app.textFields["source.search"].typeText("\n")
        app.buttons["source.back"].tap()
        XCTAssertTrue(app.textFields["search.input"].waitForExistence(timeout: 5))
        app.buttons["tab.more"].tap()
        app.buttons["more.category.Extensions"].tap()
        app.buttons["Manage Test source"].tap()
        app.buttons["Configure"].tap()
        XCTAssertTrue(app.staticTexts["No source settings"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        app.buttons["extensions.section"].tap()
        app.buttons["extensions.view.Browse"].tap()
        app.buttons["Manage Another source"].tap()
        let install = app.buttons["extensions.install.another"]
        XCTAssertTrue(install.waitForExistence(timeout: 3))
        install.tap()
        app.buttons["extensions.section"].tap()
        app.buttons["extensions.view.Installed"].tap()
        let added = app.buttons["extensions.search.another"]
        XCTAssertTrue(added.waitForExistence(timeout: 3))
        added.swipeLeft()
        app.buttons["Uninstall"].tap()
        app.alerts.buttons["Uninstall"].tap()
        XCTAssertTrue(added.waitForNonExistence(timeout: 3))
        app.buttons["extensions.section"].tap()
        app.buttons["extensions.view.Repositories"].tap()
        XCTAssertTrue(app.staticTexts["Test repository"].waitForExistence(timeout: 3))
        app.buttons["extensions.addRepository"].tap()
        XCTAssertTrue(app.textFields["extensions.repositoryURL"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
    }
}

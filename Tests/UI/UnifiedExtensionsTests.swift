import XCTest

@MainActor final class UnifiedExtensionsTests: XCTestCase {
    func testInstalledSearchSettingsAndCatalogShareOnePage() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-extensions", "--ui-testing-search"]
        app.launch()
        app.openSettings()
        XCTAssertFalse(app.buttons["more.category.Sources"].exists)
        app.openSettingsRow("more.category.Extensions")
        let source = app.buttons["extensions.search.fixture"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        // A source opens its own page: popular titles and a search inside the source.
        XCTAssertTrue(app.navigationBars["Test source"].waitForExistence(timeout: 5))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("moon\n")
        keepScreenshot("Source browse")
        app.goBack()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        // Source settings live in the row's context menu.
        source.press(forDuration: 1.0)
        let settings = app.buttons["Source Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()
        XCTAssertTrue(app.staticTexts["No Source Settings"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        let section = app.segmentedControls["extensions.section"]
        section.buttons["Browse"].tap()
        let install = app.buttons["extensions.install.another"]
        XCTAssertTrue(install.waitForExistence(timeout: 5))
        install.tap()
        section.buttons["Installed"].tap()
        let added = app.buttons["extensions.search.another"]
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        added.swipeLeft()
        app.buttons["Uninstall"].firstMatch.tap()
        // Confirm in the dialog.
        let confirm =
            app.sheets.buttons["Uninstall"].exists
            ? app.sheets.buttons["Uninstall"]
            : app.buttons.matching(identifier: "Uninstall").element(boundBy: 0)
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(added.waitForNonExistence(timeout: 5))
        section.buttons["Repositories"].tap()
        XCTAssertTrue(app.staticTexts["Test repository"].waitForExistence(timeout: 5))
        app.buttons["extensions.addRepository.row"].tap()
        XCTAssertTrue(app.textFields["extensions.repositoryURL"].waitForExistence(timeout: 3))
        keepScreenshot("Add repository")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.textFields["extensions.repositoryURL"].waitForNonExistence(timeout: 3))
    }
}

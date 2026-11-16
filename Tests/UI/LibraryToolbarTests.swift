import XCTest

/// The native Library toolbar: view menu, options menu and system search field.
@MainActor final class LibraryToolbarTests: XCTestCase {
    private func launchLibrary(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.fresh(arguments + ["-contentMode", "all"])
        app.launch()
        app.openTab("library")
        XCTAssertTrue(app.otherElements["page.library"].waitForExistence(timeout: 5))
        return app
    }

    func testViewMenuSwitchesLibraryViews() {
        let app = launchLibrary()
        let views = app.buttons["library.activeView"]
        XCTAssertTrue(views.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Library"].exists)
        views.tap()
        let starred = app.buttons["Starred"].firstMatch
        XCTAssertTrue(starred.waitForExistence(timeout: 3))
        for name in ["Saved", "Downloaded", "Reading", "Completed", "New Folder"] {
            XCTAssertTrue(app.buttons[name].firstMatch.exists, "Missing \(name)")
        }
        keepScreenshot("Library view menu")
        starred.tap()
        // The navigation title names the open view.
        XCTAssertTrue(app.navigationBars["Starred"].waitForExistence(timeout: 3))
        views.tap()
        app.buttons["Saved"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 3))
    }

    func testOptionsMenuChangesLayoutAndFilters() {
        let app = launchLibrary()
        let options = app.buttons["library.options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        for (id, title) in [
            ("compactGrid", "Compact grid"), ("covers", "Covers"), ("list", "List"),
            ("compactList", "Compact list"), ("grid", "Grid"),
        ] {
            options.tap()
            let layout = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Layout'"))
                .firstMatch
            XCTAssertTrue(layout.waitForExistence(timeout: 3))
            layout.tap()
            let choice =
                app.buttons["library.layout.\(id)"].waitForExistence(timeout: 1)
                ? app.buttons["library.layout.\(id)"] : app.buttons[title].firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 3), "Missing layout \(title)")
            if id == "compactGrid" { keepScreenshot("Library layout menu") }
            choice.tap()
            // The chosen layout is saved and shown in Settings › Library.
            options.tap()
            XCTAssertTrue(layout.waitForExistence(timeout: 3))
            XCTAssertTrue(layout.shows(title), "Layout should read \(title): \(layout.label)")
            // Close the menu without choosing anything.
            app.visibleNavigationBar.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
                .tap()
            XCTAssertTrue(options.waitForExistence(timeout: 3))
        }
        options.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Filter'")).firstMatch.tap()
        let downloaded = app.buttons["Downloaded"].firstMatch
        XCTAssertTrue(downloaded.waitForExistence(timeout: 3))
        downloaded.tap()
        XCTAssertTrue(app.buttons["Clear Filters"].firstMatch.waitForExistence(timeout: 3))
        keepScreenshot("Library filtered")
        app.buttons["Clear Filters"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No Saved Titles"].waitForExistence(timeout: 3))
    }

    func testNewFolderOpensAsAlertAndSelectsFolder() {
        let app = launchLibrary()
        app.buttons["library.options"].tap()
        app.buttons["New Folder"].firstMatch.tap()
        let alert = app.alerts["New Folder"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let name = alert.textFields.firstMatch
        name.typeText("Popup folder")
        keepScreenshot("New folder alert")
        alert.buttons["Create"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Popup folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This Folder Is Empty"].waitForExistence(timeout: 3))
        // The folder is listed in the view menu.
        app.buttons["library.activeView"].tap()
        XCTAssertTrue(app.buttons["Popup folder"].firstMatch.waitForExistence(timeout: 3))
    }

    func testLibrarySearchFiltersAndOffersSourceSearch() {
        let app = launchLibrary(["--ui-testing-search"])
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 2) {
            app.otherElements["page.library"].swipeDown()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("moon")
        XCTAssertTrue(app.staticTexts["No Matching Titles"].waitForExistence(timeout: 3))
        keepScreenshot("Library search empty")
        // The old library search handed an unmatched query to Search ("Browse
        // sources"). LibraryView still receives `onSearch` but never calls it.
        XCTAssertTrue(app.buttons["library.searchSources"].waitForExistence(timeout: 3))
    }
}

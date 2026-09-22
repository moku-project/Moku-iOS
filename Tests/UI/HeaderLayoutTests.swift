import XCTest

@MainActor final class HeaderLayoutTests: XCTestCase {
    func testNestedLibraryToolsAndSearchHandoff() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString,
            "--ui-testing-search", "-contentMode", "all",
        ]
        app.launch()
        let fab = app.buttons["library.fab"]
        XCTAssertTrue(fab.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["library.search"].exists)
        let position = fab.frame
        fab.tap()
        let add = app.buttons["library.action.Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        snapshot("Library tools root")
        add.tap()
        XCTAssertTrue(app.buttons["library.action.New folder"].waitForExistence(timeout: 3))
        XCTAssertEqual(fab.label, "Back to Library tools")
        XCTAssertEqual(fab.frame.midX, position.midX, accuracy: 1)
        snapshot("Library Add submenu")
        fab.tap()
        XCTAssertTrue(app.buttons["library.action.Views"].waitForExistence(timeout: 3))
        app.buttons["library.action.Views"].tap()
        XCTAssertTrue(app.buttons["library.action.Starred"].waitForExistence(timeout: 3))
        snapshot("Library Views submenu")
        app.buttons["library.action.Starred"].tap()
        XCTAssertTrue(app.staticTexts["Starred"].waitForExistence(timeout: 3))
        fab.tap()
        app.buttons["library.action.Filter"].tap()
        XCTAssertTrue(app.buttons["library.optionsBack"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Downloaded"].exists)
        XCTAssertFalse(app.buttons["Starred"].exists)
        app.buttons["library.optionsBack"].tap()
        XCTAssertTrue(app.buttons["library.action.Search"].waitForExistence(timeout: 3))
        app.buttons["library.action.Search"].tap()
        let input = app.textFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("moon")
        XCTAssertTrue(app.buttons["search.browseSources"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.result.moon"].exists)
        snapshot("Library search empty")
        app.buttons["search.browseSources"].tap()
        XCTAssertTrue(app.buttons["search.result.moon"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.result.garden"].exists)
        XCTAssertEqual(input.value as? String, "moon")
        app.buttons["tab.library"].tap()
        XCTAssertTrue(fab.waitForExistence(timeout: 3))
        XCTAssertEqual(fab.label, "Library tools")
        app.buttons["tab.browse"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertEqual(input.placeholderValue, "Search")
        XCTAssertEqual(input.value as? String, "moon")
    }

    func testCompactViewAndLayoutMenus() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString]
        app.launch()
        let control = app.buttons["library.layout.toggle"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.tap()
        let compact = app.buttons["library.layout.compactGrid"]
        XCTAssertTrue(compact.waitForExistence(timeout: 3))
        XCTAssertLessThan(compact.frame.width, 190)
        snapshot("Compact layout menu")
        compact.tap()
        XCTAssertEqual(control.value as? String, "Compact grid")
        for (id, title) in [
            ("covers", "Covers"), ("list", "List"), ("compactList", "Compact list"),
            ("grid", "Grid"),
        ] {
            control.tap()
            app.buttons["library.layout.\(id)"].tap()
            XCTAssertEqual(control.value as? String, title)
        }
        app.buttons["library.activeView"].tap()
        let downloaded = app.buttons["Downloaded"]
        XCTAssertTrue(downloaded.waitForExistence(timeout: 3))
        XCTAssertLessThan(downloaded.frame.width, 190)
        snapshot("Compact library view menu")
        downloaded.tap()
        XCTAssertEqual(app.buttons["library.activeView"].value as? String, "Downloaded")
    }

    func testNewFolderOpensDirectlyAsPopup() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString]
        app.launch()
        let tools = app.buttons["library.fab"]
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.tap()
        app.buttons["library.action.Add"].tap()
        app.buttons["library.action.New folder"].tap()
        let name = app.textFields["library.folderName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["library.searchFolders"].exists)
        XCTAssertTrue(app.sheets.allElementsBoundByIndex.isEmpty)
        name.tap()
        name.typeText("Popup folder")
        snapshot("New folder popup")
        app.buttons["library.createFolder"].tap()
        XCTAssertTrue(app.buttons["library.activeView"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons["library.activeView"].firstMatch.value as? String, "Popup folder")
        XCTAssertFalse(name.exists)
    }

    func testLibraryModeTabs() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString, "-contentMode", "all",
        ]
        app.launch()
        let all = app.buttons["library.mode.all"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["library.currentMode"].exists)
        for mode in ["manga", "novels", "anime"] {
            let tab = app.buttons["library.mode.\(mode)"]
            XCTAssertEqual(tab.frame.midY, all.frame.midY, accuracy: 1)
            tab.tap()
            XCTAssertTrue(tab.isSelected)
            XCTAssertFalse(all.isSelected)
        }
        snapshot("Library mode tabs")
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

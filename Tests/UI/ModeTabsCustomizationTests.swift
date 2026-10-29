import XCTest

@MainActor final class ModeTabsCustomizationTests: XCTestCase {
    func testVisibilityDragOrderAndPersistenceAcrossPages() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString,
            "--ui-testing-isolated-backend", "--ui-testing-search", "--ui-testing-extensions"]
        app.launch()
        let customize = app.buttons["library.mode.customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 10))
        let all = app.buttons["library.mode.all"]
        let manga = app.buttons["library.mode.manga"]
        XCTAssertEqual(all.frame.width, manga.frame.width, accuracy: 1)
        manga.tap()
        customize.tap()
        XCTAssertFalse(app.buttons["modes.visible.all"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["modes.reorder.all"].exists)
        app.buttons["modes.edit"].tap()
        app.buttons["modes.visible.manga"].tap()
        XCTAssertEqual(app.buttons["modes.visible.manga"].label, "Show Manga")
        let handle = app.descendants(matching: .any)["modes.reorder.anime"].firstMatch
        XCTAssertTrue(handle.exists)
        handle.press(forDuration: 0.6, thenDragTo: app.descendants(matching: .any)["modes.reorder.novels"].firstMatch)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Mode customization dropdown"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["modes.close"].tap()
        XCTAssertFalse(manga.exists)
        XCTAssertTrue(all.isSelected)
        XCTAssertLessThan(abs(customize.frame.minX - all.frame.midX), 12)
        XCTAssertLessThan(all.frame.midX, app.buttons["library.mode.anime"].frame.midX)
        XCTAssertLessThan(app.buttons["library.mode.anime"].frame.midX, app.buttons["library.mode.novels"].frame.midX)
        app.buttons["tab.more"].tap()
        app.buttons["more.category.Recent"].tap()
        XCTAssertTrue(app.buttons["recent.mode.all"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recent.mode.manga"].exists)
        XCTAssertLessThan(app.buttons["recent.mode.all"].frame.midX, app.buttons["recent.mode.anime"].frame.midX)
        XCTAssertLessThan(app.buttons["recent.mode.anime"].frame.midX, app.buttons["recent.mode.novels"].frame.midX)
        app.buttons["more.back"].tap()
        app.buttons["more.category.Extensions"].tap()
        XCTAssertTrue(app.buttons["extensions.mode.all"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["extensions.mode.manga"].exists)
        app.buttons["tab.browse"].tap()
        XCTAssertTrue(app.buttons["search.mode.all"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.mode.manga"].exists)
        app.buttons["search.mode.customize"].tap()
        XCTAssertEqual(app.buttons["modes.visible.manga"].label, "Show Manga")
        XCTAssertTrue(app.staticTexts["Pinned"].exists)
        XCTAssertTrue(app.staticTexts["Available"].exists)
        let settled = XCTAttachment(screenshot: app.screenshot())
        settled.name = "Shared mode menu in Search"
        settled.lifetime = .keepAlways
        add(settled)
        app.terminate()
        app.launch()
        XCTAssertTrue(customize.waitForExistence(timeout: 10))
        XCTAssertFalse(manga.exists)
        XCTAssertLessThan(all.frame.midX, app.buttons["library.mode.anime"].frame.midX)
        XCTAssertLessThan(app.buttons["library.mode.anime"].frame.midX, app.buttons["library.mode.novels"].frame.midX)
        customize.tap()
        app.buttons["modes.visible.manga"].tap()
        app.buttons["modes.close"].tap()
        XCTAssertTrue(manga.exists)
    }
}

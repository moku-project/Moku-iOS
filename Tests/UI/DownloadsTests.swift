import XCTest

@MainActor final class DownloadsTests: XCTestCase {
    func testRetryOnlyInExpandedTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-downloads"]
        app.launch()
        app.buttons["tab.downloads"].tap()
        let title = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Monster But Wild'")).firstMatch
        let retries = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'downloads.retry.'"))
        let retryAll = app.buttons["downloads.retryAll.monster"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(retries.count, 0)
        XCTAssertFalse(retryAll.exists)
        capture("Downloads queue collapsed")
        title.tap()
        XCTAssertTrue(retryAll.waitForExistence(timeout: 3))
        XCTAssertEqual(retries.count, 2)
        XCTAssertTrue(app.buttons["downloads.retry.3"].exists)
        capture("Downloads failed title expanded")
        retries.element(boundBy: 0).tap()
        expectation(for: NSPredicate(format: "count == 1"), evaluatedWith: retries)
        waitForExpectations(timeout: 3)
        retryAll.tap()
        expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: retries)
        waitForExpectations(timeout: 3)
        XCTAssertFalse(retryAll.exists)
        // Queue and History are a picker in the toolbar menu.
        app.buttons["downloads.activeView"].tap()
        let history = menuItem(app, "downloads.history", "History")
        XCTAssertTrue(menuItem(app, "downloads.queue", "Queue").exists)
        capture("Downloads tools menu")
        history.tap()
        let group = app.descendants(matching: .any).matching(identifier: "downloads.group.history").firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 3))
        group.tap()
        XCTAssertTrue(app.staticTexts["Chapter 12"].exists)
        capture("Downloads history")
    }

    func testEmptyDownloads() {
        let app = XCUIApplication()
        // A fresh profile and backend, so the owner's real queue can't leak in.
        app.launchArguments = [
            "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString, "--ui-testing-isolated-backend",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["tab.downloads"].waitForExistence(timeout: 10))
        app.buttons["tab.downloads"].tap()
        XCTAssertTrue(app.staticTexts["Download chapters or episodes from a title’s page to read and watch offline."]
            .waitForExistence(timeout: 10))
        capture("Downloads empty")
        // The status filter is a segmented control above the list.
        for status in ["Pending", "Completed", "Failed", "All"] {
            app.segmentedControls["downloads.status"].buttons[status].tap()
        }
        app.buttons["downloads.activeView"].tap()
        capture("Downloads tools menu")
        menuItem(app, "downloads.history", "History").tap()
        XCTAssertTrue(app.staticTexts["Finished and removed downloads will appear here."].waitForExistence(timeout: 5))
        app.buttons["downloads.activeView"].tap()
        menuItem(app, "downloads.queue", "Queue").tap()
        XCTAssertTrue(app.staticTexts["Download chapters or episodes from a title’s page to read and watch offline."]
            .waitForExistence(timeout: 5))
    }

    private func menuItem(_ app: XCUIApplication, _ id: String, _ label: String) -> XCUIElement {
        let byID = app.buttons[id]
        if byID.waitForExistence(timeout: 2) { return byID }
        let byLabel = app.buttons[label].firstMatch
        XCTAssertTrue(byLabel.waitForExistence(timeout: 3), "Missing menu item \(label)")
        return byLabel
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

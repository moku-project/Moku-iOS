import XCTest

@MainActor final class DownloadsTests: XCTestCase {
    func testRetryOnlyInExpandedTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-downloads"]
        app.launch()
        app.buttons["tab.downloads"].tap()
        let title = app.buttons["downloads.group.monster"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["downloads.retry.3"].exists)
        XCTAssertFalse(app.buttons["downloads.retryAll.monster"].exists)
        capture("Downloads queue collapsed")
        title.tap()
        XCTAssertTrue(app.buttons["downloads.retry.3"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["downloads.retryAll.monster"].exists)
        capture("Downloads failed title expanded")
        app.buttons["downloads.retry.3"].tap()
        XCTAssertFalse(app.buttons["downloads.retry.3"].exists)
        XCTAssertTrue(app.buttons["downloads.retry.4"].exists)
        app.buttons["downloads.retryAll.monster"].tap()
        XCTAssertFalse(app.buttons["downloads.retry.4"].exists)
        XCTAssertFalse(app.buttons["downloads.retryAll.monster"].exists)
        // The view switcher offers only the view that isn't showing.
        app.buttons["downloads.activeView"].tap()
        XCTAssertTrue(app.buttons["downloads.history"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["downloads.history"].label, "History")
        XCTAssertFalse(app.buttons["downloads.queue"].exists)
        capture("Downloads compact view menu")
        app.buttons["downloads.history"].tap()
        XCTAssertEqual(app.buttons["downloads.activeView"].value as? String, "History")
        app.buttons["downloads.group.history"].tap()
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
        app.buttons["downloads.activeView"].tap()
        XCTAssertTrue(app.buttons["downloads.history"].waitForExistence(timeout: 3))
        capture("Downloads compact view menu")
        app.buttons["downloads.history"].tap()
        XCTAssertTrue(app.staticTexts["Finished and removed downloads will appear here."].waitForExistence(timeout: 5))
        app.buttons["downloads.activeView"].tap()
        XCTAssertTrue(app.buttons["downloads.queue"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["downloads.queue"].label, "Queue")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

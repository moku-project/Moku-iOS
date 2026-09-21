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
        app.buttons["downloads.activeView"].tap()
        XCTAssertEqual(app.buttons["downloads.queue"].label, "Queue")
        XCTAssertEqual(app.buttons["downloads.history"].label, "History")
        capture("Downloads compact view menu")
        app.buttons["downloads.history"].tap()
        app.buttons["downloads.group.history"].tap()
        XCTAssertTrue(app.staticTexts["Chapter 12"].exists)
        capture("Downloads history")
    }

    func testEmptyDownloads() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["tab.downloads"].tap()
        XCTAssertTrue(app.staticTexts["No downloads in queue."].waitForExistence(timeout: 5))
        capture("Downloads empty")
        app.buttons["downloads.activeView"].tap()
        XCTAssertEqual(app.buttons["downloads.queue"].label, "Queue")
        XCTAssertEqual(app.buttons["downloads.history"].label, "History")
        capture("Downloads compact view menu")
        app.buttons["downloads.history"].tap()
        XCTAssertTrue(app.staticTexts["No completed downloads."].exists)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

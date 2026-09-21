import XCTest

@MainActor final class RecentUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-profiles", "--ui-testing-home-populated", "--ui-testing-recent",
            "-mokuProfileTestID", UUID().uuidString,
        ]
        app.launch()
        XCTAssertTrue(app.buttons["tab.more"].waitForExistence(timeout: 10))
        app.buttons["tab.more"].tap()
        app.buttons["more.category.Recent"].tap()
        XCTAssertTrue(app.buttons["recent.activeView"].firstMatch.waitForExistence(timeout: 5))
        return app
    }
    func testHistorySearchExpansionUpdatesAndModes() {
        let app = launch()
        capture("Recent history")
        app.buttons["Actions for I’m Not That Kind of Talent"].firstMatch.tap()
        app.buttons["Show chapters"].tap()
        XCTAssertTrue(app.buttons["Clear title history"].firstMatch.exists)
        capture("Recent expanded history")
        app.buttons["recent.fab"].tap()
        app.buttons["recent.action.Search"].tap()
        let search = app.textFields["recent.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("No matching fixture")
        app.buttons["Apply"].tap()
        XCTAssertTrue(app.staticTexts["No matching activity"].waitForExistence(timeout: 3))
        app.buttons["Search active"].tap()
        app.buttons["Reset"].tap()
        app.buttons["Apply"].tap()
        app.buttons["recent.activeView"].firstMatch.tap()
        app.buttons["recent.view.Updates"].tap()
        let expand = app.buttons["Expand I’m Not That Kind of Talent updates"]
        XCTAssertTrue(expand.waitForExistence(timeout: 3))
        expand.tap()
        XCTAssertTrue(app.buttons["Download Chapter 14"].exists)
        capture("Recent updates")
        app.buttons["Download Chapter 14"].tap()
        XCTAssertTrue(app.staticTexts["Download queued."].waitForExistence(timeout: 3))
        app.alerts.buttons["OK"].tap()
        app.buttons["recent.mode.anime"].tap()
        XCTAssertFalse(expand.exists)
        let anime = app.buttons["Expand Monster But Wild updates"]
        XCTAssertTrue(anime.waitForExistence(timeout: 3))
        anime.tap()
        XCTAssertTrue(app.buttons["Open Episode 12"].exists)
        capture("Recent anime updates")
        app.buttons["recent.fab"].tap()
        app.buttons["recent.action.Refresh"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
    }
    func testClearHistoryRequiresConfirmation() {
        let app = launch()
        app.buttons["recent.fab"].tap()
        app.buttons["recent.action.Clear history"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Resume I’m Not That Kind of Talent"].exists)
        app.buttons["recent.fab"].tap()
        app.buttons["recent.action.Clear history"].tap()
        app.buttons["recent.confirmClear"].tap()
        XCTAssertTrue(app.staticTexts["Nothing here yet"].waitForExistence(timeout: 3))
        capture("Recent empty history")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor final class TrackingUITests: XCTestCase {
    func testServicesMenusAndDisconnectConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-profiles", "--ui-testing-tracking",
            "-mokuProfileTestID", UUID().uuidString,
        ]
        app.launch()
        XCTAssertTrue(app.buttons["tab.more"].waitForExistence(timeout: 10))
        app.buttons["tab.more"].tap()
        app.buttons["more.category.Tracking"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Coming soon"].exists)
        capture("Tracking services")
        app.buttons["tracking.fab"].tap()
        XCTAssertTrue(app.buttons["tracking.action.Import list"].waitForExistence(timeout: 3))
        capture("Tracking radial menu")
        app.buttons["tracking.action.Import list"].tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 3))
        capture("Tracking import setup")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Ready to import"].waitForExistence(timeout: 3))
        capture("Tracking import review")
        app.buttons["Import 1"].tap()
        XCTAssertTrue(app.staticTexts["Imported"].waitForExistence(timeout: 5))
        app.buttons["Save & close"].tap()
        app.buttons["Actions for AniList"].tap()
        app.buttons["Disconnect"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].exists)
        app.buttons["Actions for AniList"].tap()
        app.buttons["Disconnect"].tap()
        app.buttons["Disconnect"].tap()
        XCTAssertTrue(app.staticTexts["Not connected"].waitForExistence(timeout: 3))
        app.buttons["Actions for AniList"].tap()
        app.buttons["Connect"].tap()
        XCTAssertTrue(app.secureTextFields["tracking.token"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

import XCTest

@MainActor
final class HomeTests: XCTestCase {
    func testEmptyHomeWelcomesAndShowsZeroStats() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-home-empty"]
        app.launch()
        app.buttons["tab.home"].tap()
        XCTAssertTrue(app.scrollViews["home.scroll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Home"].exists)
        XCTAssertTrue(app.staticTexts["Start Your Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Streak"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.heatmap"].exists)
        XCTAssertTrue(app.staticTexts["Nothing queued yet"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home.recent"].exists)
        capture("Home — empty")
        app.buttons["Find Something"].tap()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: app.buttons["tab.browse"])
        waitForExpectations(timeout: 3)
    }

    func testPopulatedHomeFollowsTheAndroidLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-home-populated"]
        app.launch()
        app.buttons["tab.home"].tap()
        XCTAssertTrue(app.scrollViews["home.scroll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["I’m Not That Kind of Talent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.continue.resume"].exists)
        XCTAssertTrue(app.staticTexts["Continue Reading"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home.carousel"].exists)
        let upNext = app.descendants(matching: .any)["home.upNext"]
        XCTAssertTrue(upNext.exists)
        XCTAssertTrue(upNext.buttons.firstMatch.label.contains("Monster But Wild"))
        capture("Home — populated")
        app.buttons["home.continue.details"].tap()
        let details = app.descendants(matching: .any)["search.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        app.goBack()
        XCTAssertTrue(details.waitForNonExistence(timeout: 5))
        let recent = app.descendants(matching: .any)["home.recent"]
        app.scrollViews["home.scroll"].swipeUp()
        XCTAssertTrue(recent.waitForExistence(timeout: 3))
        XCTAssertTrue(recent.buttons.firstMatch.label.contains("Overgeared"))
        capture("Home — populated, scrolled")
    }

    func testSingleTitleHasNothingQueued() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-home-one"]
        app.launch()
        app.buttons["tab.home"].tap()
        XCTAssertTrue(app.buttons["home.continue.resume"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing queued yet"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home.recent"].exists)
        XCTAssertFalse(app.staticTexts["Start Your Library"].exists)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

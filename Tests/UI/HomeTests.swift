import XCTest

@MainActor
final class HomeTests: XCTestCase {
    func testEmptyHomeCarouselAndStats() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-home-empty"]
        app.launch()
        app.buttons["tab.home"].tap()
        XCTAssertTrue(app.scrollViews["home.scroll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing here yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No chapters to show"].exists)
        let header = app.staticTexts.matching(identifier: "header.title").matching(NSPredicate(format: "label == %@", "Home")).firstMatch
        XCTAssertLessThanOrEqual(header.frame.height, 56)
        let carousel = app.otherElements["home.carousel"]
        if carousel.exists {
            XCTAssertLessThanOrEqual(carousel.frame.minY - header.frame.maxY, 24)
        }
        capture("Home — empty carousel")
        XCTAssertFalse(app.buttons["Slot 2"].exists)
        XCTAssertFalse(app.buttons["Next title"].exists)
        XCTAssertFalse(app.buttons["Pause title rotation"].exists)
        let scroll = app.scrollViews["home.scroll"]
        scroll.swipeUp()
        scroll.swipeUp()
        XCTAssertTrue(app.staticTexts["No completed chapters or episodes yet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Series started"].exists)
        scroll.swipeUp()
        let finalRow = app.staticTexts["No completed chapters or episodes yet"]
        XCTAssertTrue(finalRow.exists)
        XCTAssertLessThanOrEqual(finalRow.frame.maxY + 12, app.buttons["tab.home"].frame.minY)
        capture("Home — empty activity and stats")
        app.buttons["tab.library"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()
        let selected = NSPredicate(format: "isSelected == true")
        expectation(for: selected, evaluatedWith: app.buttons["tab.library"])
        waitForExpectations(timeout: 3)
    }

    func testPopulatedHomeCarouselAndChapterDetails() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-home-populated"]
        app.launch()
        app.buttons["tab.home"].tap()
        XCTAssertTrue(app.scrollViews["home.scroll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["I’m Not That Kind of Talent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Resume"].exists)
        capture("Home — sample history")
        app.buttons["All chapters"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["details.back"].waitForExistence(timeout: 5))
        let done = app.buttons["details.back"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        app.otherElements["home.carousel"].swipeLeft()
        XCTAssertTrue(app.staticTexts["Watching"].waitForExistence(timeout: 3))
        let scroll = app.scrollViews["home.scroll"]
        scroll.swipeUp()
        scroll.swipeUp()
        scroll.swipeUp()
        capture("Home — sample activity and stats")
    }

    func testSingleTitleHasNoCarouselControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-home-one"]
        app.launch()
        app.buttons["tab.home"].tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Slot 2"].exists)
        XCTAssertFalse(app.buttons["Next title"].exists)
        XCTAssertFalse(app.buttons["Pause title rotation"].exists)
        XCTAssertFalse(app.staticTexts["Nothing here yet"].exists)
    }

    func testTwoTitlesRotateAndWrapWithoutEmptySlots() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-home-two"]
        app.launch()
        app.buttons["tab.home"].tap()
        let carousel = app.otherElements["home.carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Slot 1"].exists)
        XCTAssertFalse(app.buttons["Next title"].exists)
        XCTAssertFalse(app.buttons["Pause title rotation"].exists)
        expectation(for: NSPredicate(format: "value == %@", "Title 2 of 2"), evaluatedWith: carousel)
        waitForExpectations(timeout: 15)
        expectation(for: NSPredicate(format: "value == %@", "Title 1 of 2"), evaluatedWith: carousel)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(app.staticTexts["Nothing here yet"].exists)
        capture("Home — two populated carousel slots")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

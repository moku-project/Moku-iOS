import XCTest

@MainActor
final class HomeTests: XCTestCase {
    func testEmptyHomeCarouselAndStats() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-home-empty"]
        app.launch()
        app.buttons["tab.home"].tap()
        XCTAssertTrue(app.staticTexts["Nothing here yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No chapters to show"].exists)
        let header = app.navigationBars["Home"]
        XCTAssertLessThanOrEqual(header.frame.height, 56)
        let carousel = app.otherElements["home.carousel"]
        if carousel.exists {
            XCTAssertLessThanOrEqual(carousel.frame.minY - header.frame.maxY, 16)
        }
        capture("Home — empty carousel")
        app.buttons["Slot 2"].tap()
        XCTAssertTrue(
            app.staticTexts["Pin a title or keep reading to fill this slot."].waitForExistence(
                timeout: 3))
        app.buttons["Slot 1"].tap()
        let scroll = app.scrollViews["home.scroll"]
        scroll.swipeUp()
        scroll.swipeUp()
        XCTAssertTrue(app.staticTexts["No reading tracked yet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Series started"].exists)
        scroll.swipeUp()
        let finalRow = app.staticTexts["Updated —"]
        XCTAssertTrue(finalRow.isHittable)
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
        XCTAssertTrue(app.staticTexts["I’m Not That Kind of Talent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Resume"].exists)
        capture("Home — sample history")
        app.buttons["All chapters"].tap()
        XCTAssertTrue(app.navigationBars["Title details"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Chapter 15"].exists)
        let done = app.buttons["home.details.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Slot 2"].tap()
        XCTAssertTrue(app.staticTexts["WATCHING"].waitForExistence(timeout: 3))
        let scroll = app.scrollViews["home.scroll"]
        scroll.swipeUp()
        scroll.swipeUp()
        scroll.swipeUp()
        capture("Home — sample activity and stats")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

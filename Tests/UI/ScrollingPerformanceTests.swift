import XCTest

@MainActor final class ScrollingPerformanceTests: XCTestCase {
    func testSettingsScrollingWithSourceRuntime() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString,
            "--ui-testing-search", "--ui-testing-isolated-backend", "--ui-testing-start-runtime",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 15))
        app.buttons["tab.home"].tap()
        let settings = app.buttons.matching(identifier: "header.settings").allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(settings)
        settings?.tap()
        let scroll = app.scrollViews["settings.index"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app), XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            scroll.swipeUp()
            scroll.swipeUp()
            scroll.swipeDown()
            scroll.swipeDown()
        }
        XCTAssertTrue(app.buttons["settings.category.General"].isHittable)
        app.buttons["settings.category.General"].tap()
        XCTAssertTrue(app.buttons["settings.back"].waitForExistence(timeout: 5))
    }
}

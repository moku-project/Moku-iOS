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
        app.openSettings()
        let scroll = app.settingsIndex
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(
            metrics: [
                XCTCPUMetric(application: app), XCTMemoryMetric(application: app),
                XCTOSSignpostMetric.scrollDecelerationMetric,
            ], options: options
        ) {
            scroll.swipeUp()
            scroll.swipeUp()
            scroll.swipeDown()
            scroll.swipeDown()
        }
        app.openSettingsRow("settings.category.General")
        XCTAssertTrue(app.navigationBars["General"].waitForExistence(timeout: 5))
    }
}

import XCTest

@MainActor final class PageSwitchingTests: XCTestCase {
    func testTabFrameLatency() {
        checkTabFrameLatency(largeChapterList: false)
    }

    func testTabFrameLatencyWithTwoThousandChapters() {
        checkTabFrameLatency(largeChapterList: true)
    }

    private func checkTabFrameLatency(largeChapterList: Bool) {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString,
            "--ui-testing-isolated-backend", "--ui-testing-search", "--ui-testing-home-populated",
            "--ui-testing-navigation-timing", "--ui-testing-slow-discovery",
        ]
        if largeChapterList { app.launchArguments.append("--ui-testing-home-large-chapters") }
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
        if largeChapterList {
            app.buttons["tab.home"].tap()
            XCTAssertTrue(app.staticTexts["Ch.1"].firstMatch.waitForExistence(timeout: 10))
        }
        let probe = app.otherElements["navigation.frameLatency"]
        for tab in ["home", "browse", "downloads", "more", "library", "home", "browse", "more", "library"] {
            app.buttons["tab.\(tab)"].tap()
            let ready = NSPredicate(format: "value BEGINSWITH %@", tab + ":")
            expectation(for: ready, evaluatedWith: probe)
            waitForExpectations(timeout: 5)
            let result = probe.value as? String ?? ""
            print("TAB_FRAME_LATENCY \(result)")
            let timing = XCTAttachment(string: result)
            timing.name = "Tab frame latency"
            timing.lifetime = .keepAlways
            add(timing)
            let milliseconds = Int(result.split(separator: ":").last ?? "") ?? 10_000
            XCTAssertLessThan(milliseconds, 500, "Tab selection should present promptly: \(result)")
        }
    }

    func testReadyHomeAppearsWithoutWaitingForSkeletonAnimation() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString,
            "--ui-testing-isolated-backend", "--ui-testing-search", "--ui-testing-home-empty",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
        for _ in 0..<3 {
            app.buttons["tab.home"].tap()
            XCTAssertTrue(app.staticTexts["Nothing here yet"].exists || app.staticTexts["Nothing here yet"].waitForExistence(timeout: 1))
            app.buttons["tab.library"].tap()
            XCTAssertTrue(app.buttons["tab.library"].isSelected)
        }
    }
}

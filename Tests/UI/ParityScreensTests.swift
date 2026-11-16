import XCTest

/// Opens the screens added in the final parity pass and keeps a screenshot of
/// each, so layout can be reviewed without driving the app by hand.
@MainActor final class ParityScreensTests: XCTestCase {
    func testNewSettingsScreensOpenAndClose() {
        let app = XCUIApplication.fresh(["--ui-testing-search", "--ui-testing-isolated-backend"])
        app.launch()
        app.openSettings()

        app.openSettingsRow("settings.category.Server")
        let logButton = app.buttons["server.log.open"]
        XCTAssertTrue(logButton.waitForExistence(timeout: 10), "step 1")
        capture("Server settings with log row")
        logButton.tap()
        XCTAssertTrue(app.navigationBars["Server log"].waitForExistence(timeout: 5), "step 2")
        sleep(1)
        capture("Server log")
        app.navigationBars["Server log"].buttons["Done"].tap()
        app.goBack()

        app.openSettingsRow("more.category.About")
        let report = app.buttons["Report an Issue"].firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5), "step 3")
        app.reveal(report, in: app.collectionViews.firstMatch)
        report.tap()
        XCTAssertTrue(app.navigationBars["Report an issue"].waitForExistence(timeout: 5), "step 4")
        capture("Report an issue")
        app.navigationBars["Report an issue"].buttons["Cancel"].tap()
        app.goBack()

        app.openSettingsRow("settings.category.Storage")
        let local = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Local titles"))
            .firstMatch
        // The Storage list builds rows lazily, so scroll to the row before checking it.
        app.reveal(local, in: app.collectionViews["settings.scroll"])
        XCTAssertTrue(local.waitForExistence(timeout: 5), "step 5")
        local.tap()
        XCTAssertTrue(app.navigationBars["Local titles"].waitForExistence(timeout: 5), "step 6")
        sleep(1)
        capture("Local titles")
        app.navigationBars["Local titles"].buttons["Done"].tap()
        app.goBack()

        app.openSettingsRow("settings.category.Folders")
        XCTAssertTrue(app.navigationBars["Folders"].waitForExistence(timeout: 5), "step 7")
        capture("Folders")
    }

    func testReaderShowsResumeBannerAtSavedPage() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reader"]
        app.launch()
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: 10))
        app.buttons["reader.settings"].tap()
        Thread.sleep(forTimeInterval: 0.35)
        app.buttons["reader.option.single"].tap()
        app.buttons["reader.drawer.close"].tap()
        for _ in 0..<3 { app.buttons["reader.next"].tap() }
        XCTAssertTrue((app.sliders["reader.page"].value as? String ?? "").contains("4 of 12"))
        app.buttons["reader.close"].tap()
        app.terminate()
        app.launchArguments = ["--ui-testing-reader", "--reader-keep-preferences"]
        app.launch()
        let banner = app.buttons["reader.resumed"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        XCTAssertTrue(banner.label.contains("Resumed on page 4"))
        capture("Reader resume banner")
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: banner)
        waitForExpectations(timeout: 6)
    }

    func testReaderOpensPDFChapter() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reader", "--ui-testing-reader-pdf"]
        app.launch()
        let page = app.sliders["reader.page"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        XCTAssertTrue((page.value as? String ?? "").contains("of 3"))
        XCTAssertFalse(
            app.staticTexts["Page 1 unavailable. Tap to retry."].waitForExistence(timeout: 3))
        capture("Reader PDF chapter")
    }

    func testPlayerShowsStyledASSSubtitles() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        // Start paused at 100%, so the controls stay up and sizes are predictable.
        app.launchArguments = [
            "--ui-testing-player", "-player.autoplay", "NO", "-player.subtitleScale", "1",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["player.subtitles"].waitForExistence(timeout: 10))
        // Like the player tests: wait until the episode has loaded before opening menus.
        expectation(
            for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["player.play"])
        waitForExpectations(timeout: 10)
        app.buttons["player.subtitles"].tap()
        XCTAssertTrue(app.buttons["Signs (ASS)"].waitForExistence(timeout: 3))
        app.buttons["Signs (ASS)"].tap()
        XCTAssertTrue(app.staticTexts["Northbound platform"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A quiet moment before the journey."].exists)
        let sign = app.staticTexts["Northbound platform"].frame
        let line = app.staticTexts["A quiet moment before the journey."].frame
        XCTAssertLessThan(sign.midY, line.midY, "The {\\an8} sign belongs above the dialogue")
        // Karaoke lines read as one line of text.
        XCTAssertTrue(app.staticTexts["Sing along"].exists)
        capture("Player ASS subtitles")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

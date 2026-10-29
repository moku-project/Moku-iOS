import XCTest

@MainActor
final class SearchTests: XCTestCase {
    func testDiscoveryCarouselRotatesWithoutControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString]
        app.launch()
        app.buttons["tab.browse"].tap()
        XCTAssertTrue(app.staticTexts["Popular right now"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.discovery.page.1"].exists)
        XCTAssertFalse(app.buttons["search.discovery.pause"].exists)
        XCTAssertFalse(app.staticTexts["Inspired by the genres you’ve been reading."].exists)
        XCTAssertTrue(app.staticTexts["Popular right now"].exists)
        XCTAssertTrue(app.buttons["search.latest.fresh-1"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Latest updates"].exists)
        XCTAssertTrue(app.staticTexts["More to explore"].exists)
        XCTAssertFalse(app.staticTexts["Popular right now"].exists)
        XCTAssertFalse(app.buttons["search.popular.moon"].exists)
        screenshot("Search discovery — alternate sections")
        XCTAssertTrue(app.buttons["search.popular.moon"].waitForExistence(timeout: 15))
    }

    func testDiscoveryPageHasPopularAndSharedModesWithoutOpeningKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString]
        app.launch()
        app.buttons["tab.browse"].tap()
        XCTAssertTrue(app.staticTexts["Popular right now"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.popular.moon"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.buttons["search.close"].exists)
        for mode in ["all", "manga", "novels", "anime"] {
            XCTAssertTrue(app.buttons["search.mode.\(mode)"].exists)
        }
        app.buttons["search.mode.novels"].tap()
        XCTAssertTrue(app.buttons["search.popular.garden"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.popular.moon"].exists)
        app.buttons["tab.library"].tap()
        app.buttons["tab.browse"].tap()
        XCTAssertTrue(app.buttons["search.mode.novels"].isSelected)
        screenshot("Search discovery")
    }

    func testNavigationWithEmbeddedRuntimeStartup() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-isolated-backend", "--ui-testing-start-runtime",
            "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString,
        ]
        app.launch()
        for _ in 0..<2 {
            let settingsStart = ContinuousClock.now
            app.buttons["header.settings"].firstMatch.tap()
            XCTAssertTrue(
                app.scrollViews["settings.index"].exists
                    || app.scrollViews["settings.index"].waitForExistence(timeout: 1))
            let settingsDuration = settingsStart.duration(to: .now)
            print("Settings navigation including XCTest tap: \(settingsDuration)")
            XCTAssertLessThan(settingsDuration, .seconds(2))
            app.buttons["account.back"].tap()
            let searchStart = ContinuousClock.now
            app.buttons["tab.browse"].tap()
            XCTAssertTrue(
                app.textFields["search.input"].exists
                    || app.textFields["search.input"].waitForExistence(timeout: 1))
            let searchDuration = searchStart.duration(to: .now)
            print("Search navigation including XCTest tap: \(searchDuration)")
            XCTAssertLessThan(searchDuration, .seconds(2))
            app.textFields["search.input"].tap()
            app.textFields["search.input"].typeText("\n")
            app.buttons["tab.library"].tap()
        }
        app.buttons["tab.more"].tap()
        app.buttons["more.category.Extensions"].tap()
        XCTAssertTrue(app.buttons["extensions.section"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["extensions.browse"].waitForExistence(timeout: 3))
        app.buttons["extensions.browse"].tap()
        XCTAssertTrue(app.staticTexts["Add your first repository"].waitForExistence(timeout: 3))
    }

    func testSearchReadsInstalledSourcesWithoutStartingJava() {
        let app = XCUIApplication()
        // Exercise the real SQLite/GraphQL service without installing extensions
        // or touching the user's backend database.
        app.launchArguments = ["--ui-testing-isolated-backend", "-contentMode", "all"]
        app.launch()
        app.buttons["tab.browse"].tap()
        let input = app.textFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("moon\n")
        XCTAssertTrue(
            app.staticTexts[
                "No sources installed. Open Extensions from the More menu to add one."
            ].waitForExistence(timeout: 60))
        app.buttons["tab.library"].tap()
        XCTAssertTrue(app.buttons["tab.library"].waitForExistence(timeout: 3))
    }

    func testGlobalBrowseDoesNotInheritNovelLibraryMode() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "-contentMode", "novels"]
        app.launch()
        app.buttons["tab.browse"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let input = app.textFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("moon")
        XCTAssertTrue(app.buttons["search.result.moon"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.result.garden"].exists)
        XCTAssertEqual(app.buttons["search.filter"].value as? String, "0 active filters")
    }

    func testDebouncedSearchPanelsAndTopBar() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "-contentMode", "all"]
        app.launch()
        app.buttons["tab.browse"].tap()
        let input = app.textFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("moon")
        XCTAssertTrue(app.buttons["search.result.moon"].waitForExistence(timeout: 5))
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(keyboard.frame.minY - input.frame.maxY, 24)
        XCTAssertFalse(app.buttons["search.sort"].exists)
        let filter = app.buttons["search.filter"]
        XCTAssertFalse(app.buttons["search.close"].exists)
        XCTAssertLessThan(input.frame.maxX, filter.frame.minX)
        XCTAssertLessThan(input.frame.maxY, app.buttons["search.result.moon"].frame.minY)
        XCTAssertFalse(app.staticTexts["search.context"].exists)
        input.typeText("\n")
        XCTAssertTrue(app.buttons["search.result.moon"].waitForExistence(timeout: 5))
        screenshot("Search results")
        filter.tap()
        XCTAssertFalse(app.buttons["search.result.moon"].exists)
        let mangaFilter = app.scrollViews.buttons["Manga"]
        XCTAssertTrue(mangaFilter.waitForExistence(timeout: 3))
        mangaFilter.tap()
        let apply = app.buttons["search.apply"]
        let cancel = app.buttons["search.cancelOptions"]
        let reset = app.buttons["search.resetOptions"]
        let actionY = apply.frame.midY
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(apply.isHittable)
        XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(reset.isHittable)
        XCTAssertEqual(apply.frame.midY, actionY, accuracy: 2)
        screenshot("Search filters")
        app.buttons["search.apply"].tap()
        XCTAssertTrue(app.buttons["search.result.moon"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.result.garden"].exists)
        filter.tap()
        XCTAssertFalse(app.buttons["search.result.moon"].exists)
        app.buttons["Title Z–A"].tap()
        app.buttons["search.cancelOptions"].tap()
        XCTAssertTrue(app.buttons["search.result.moon"].exists)
        app.buttons["tab.library"].tap()
        app.buttons["tab.browse"].tap()
        XCTAssertEqual(input.value as? String, "moon")
        XCTAssertTrue(app.buttons["search.result.moon"].exists)
        XCTAssertFalse(app.buttons["search.result.garden"].exists)
        XCTAssertTrue(app.buttons["tab.browse"].isSelected)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
final class LiveSearchTests: XCTestCase {
    func testEmbeddedMangaDexSearch() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MOKU_LIVE_SEARCH"] == "1",
            "Set TEST_RUNNER_MOKU_LIVE_SEARCH=1 for this network integration test.")
        let app = XCUIApplication()
        app.launchArguments = ["-contentMode", "all", "--ui-testing-isolated-backend"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.browse"].waitForExistence(timeout: 15))
        app.buttons["tab.more"].tap()
        app.buttons["more.category.Extensions"].tap()
        app.buttons["extensions.section"].tap()
        app.buttons["extensions.view.Repositories"].tap()
        XCTAssertTrue(app.buttons["extensions.addRepository"].waitForExistence(timeout: 10))
        app.buttons["extensions.addRepository"].tap()
        let repositoryURL = app.textFields["extensions.repositoryURL"]
        XCTAssertTrue(repositoryURL.waitForExistence(timeout: 5))
        repositoryURL.tap()
        repositoryURL.typeText(
            "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb")
        app.buttons["Add"].tap()
        XCTAssertTrue(repositoryURL.waitForNonExistence(timeout: 120))
        app.buttons["extensions.section"].tap()
        app.buttons["extensions.view.Browse"].tap()
        app.buttons["extensions.fab"].tap()
        app.buttons["extensions.action.Search"].tap()
        let catalogQuery = app.textFields["extensions.query"]
        catalogQuery.tap()
        catalogQuery.typeText("MangaDex")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Manage MangaDex"].waitForExistence(timeout: 30))
        app.buttons["Manage MangaDex"].tap()
        let install = app.buttons["extensions.install.eu.kanade.tachiyomi.extension.all.mangadex"]
        XCTAssertTrue(install.waitForExistence(timeout: 30))
        install.tap()
        XCTAssertTrue(app.buttons["Manage MangaDex"].waitForExistence(timeout: 120))
        app.buttons["extensions.section"].tap()
        app.buttons["extensions.view.Installed"].tap()
        let source = app.buttons["extensions.search.eu.kanade.tachiyomi.extension.all.mangadex"]
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        app.buttons["Manage MangaDex"].tap()
        app.buttons["Configure"].tap()
        XCTAssertTrue(app.navigationBars["MangaDex"].waitForExistence(timeout: 10))
        let dataSaver = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Data saver")
        )
        .firstMatch
        XCTAssertTrue(dataSaver.waitForExistence(timeout: 10))
        dataSaver.tap()
        let toggle = app.switches["Data saver"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let previousValue = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertNotEqual(
            toggle.value as? String, previousValue, "The switch must change before saving")
        app.buttons["Save"].tap()
        XCTAssertTrue(dataSaver.waitForExistence(timeout: 10))
        dataSaver.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertNotEqual(toggle.value as? String, previousValue)
        app.buttons["Cancel"].tap()
        let settingsCapture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        settingsCapture.name = "Source settings"
        settingsCapture.lifetime = .keepAlways
        add(settingsCapture)
        app.buttons["Done"].tap()
        source.tap()

        let input = app.textFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Rent a Girlfriend")
        input.typeText("\n")
        XCTAssertTrue(app.staticTexts["Rent-A-Girlfriend"].waitForExistence(timeout: 180))
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Live MangaDex search"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["tab.more"].tap()
        app.buttons["more.category.Extensions"].tap()
        XCTAssertTrue(app.buttons["Manage MangaDex"].waitForExistence(timeout: 15))
        source.swipeLeft()
        app.buttons["Uninstall"].tap()
        app.alerts.buttons["Uninstall"].tap()
        XCTAssertTrue(app.buttons["extensions.browse"].waitForExistence(timeout: 10))
        app.buttons["extensions.browse"].tap()
        app.buttons["Manage MangaDex"].tap()
        XCTAssertTrue(install.waitForExistence(timeout: 30))

    }
}

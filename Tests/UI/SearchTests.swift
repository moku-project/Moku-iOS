import XCTest

@MainActor
final class SearchTests: XCTestCase {
    func testPopularGridFollowsContentButtonWithoutOpeningKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-search", "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString,
        ]
        app.launch()
        app.buttons["tab.browse"].tap()
        XCTAssertTrue(app.buttons["search.popular.moon"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Popular right now"].exists)
        XCTAssertFalse(app.staticTexts["Recommended for you"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        XCTAssertTrue(app.buttons["search.sources"].exists)
        NavigationTests.chooseMode("Novels", in: app)
        XCTAssertTrue(app.buttons["search.popular.garden"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.popular.moon"].exists)
        app.buttons["tab.library"].tap()
        app.buttons["tab.browse"].tap()
        XCTAssertEqual(app.buttons["mode.button"].value as? String, "Novels")
        XCTAssertTrue(app.buttons["search.popular.garden"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.popular.moon"].exists)
        screenshot("Search popular")
    }

    func testNavigationWithEmbeddedRuntimeStartup() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-isolated-backend", "--ui-testing-start-runtime",
            "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString,
        ]
        app.launch()
        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 15))
        for _ in 0..<2 {
            let settingsStart = ContinuousClock.now
            app.buttons["tab.settings"].tap()
            XCTAssertTrue(
                app.settingsIndex.exists || app.settingsIndex.waitForExistence(timeout: 1))
            let settingsDuration = settingsStart.duration(to: .now)
            print("Settings navigation including XCTest tap: \(settingsDuration)")
            XCTAssertLessThan(settingsDuration, .seconds(2))
            let searchStart = ContinuousClock.now
            app.buttons["tab.browse"].tap()
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.exists || field.waitForExistence(timeout: 1))
            let searchDuration = searchStart.duration(to: .now)
            print("Search navigation including XCTest tap: \(searchDuration)")
            XCTAssertLessThan(searchDuration, .seconds(2))
            field.tap()
            field.typeText("\n")
            // Close the search so the tab bar returns from under the keyboard.
            if app.keyboards.firstMatch.exists { app.visibleNavigationBar.buttons["Close"].tap() }
            app.buttons["tab.library"].tap()
        }
        app.openSettings()
        app.openSettingsRow("more.category.Extensions")
        let section = app.segmentedControls["extensions.section"]
        XCTAssertTrue(section.waitForExistence(timeout: 3))
        section.buttons["Browse"].tap()
        XCTAssertTrue(section.buttons["Browse"].isSelected)
        XCTAssertTrue(
            app.staticTexts["Add a repository to find extensions"].waitForExistence(timeout: 10))
    }

    func testSearchReadsInstalledSourcesWithoutStartingJava() {
        let app = XCUIApplication()
        // Exercise the real SQLite/GraphQL service without installing extensions
        // or touching the user's backend database.
        app.launchArguments = ["--ui-testing-isolated-backend", "-contentMode", "all"]
        app.launch()
        app.buttons["tab.browse"].tap()
        let input = app.searchFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("moon\n")
        XCTAssertTrue(
            app.staticTexts[
                "No sources installed. Open Settings → Extensions to add one."
            ].waitForExistence(timeout: 60))
        if app.keyboards.firstMatch.exists { app.visibleNavigationBar.buttons["Close"].tap() }
        app.buttons["tab.library"].tap()
        XCTAssertTrue(app.buttons["tab.library"].waitForExistence(timeout: 3))
    }

    /// Search looks for the content type chosen with the tab bar's content button.
    func testGlobalSearchFollowsContentButton() {
        let app = XCUIApplication()
        // A launch-argument contentMode would shadow every later change, so choose it with the button.
        app.launchArguments = [
            "--ui-testing-search", "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString,
        ]
        app.launch()
        NavigationTests.chooseMode("Novels", in: app)
        app.buttons["tab.browse"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let input = app.searchFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("moon")
        XCTAssertTrue(app.buttons["search.result.garden"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.result.moon"].exists)
        // The tab bar hides under the keyboard; scroll the results to put it away.
        dismissKeyboard(app)
        NavigationTests.chooseMode("All", in: app)
        XCTAssertTrue(app.buttons["search.result.moon"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.result.garden"].exists)
    }

    func testDebouncedSearchPanelsAndTopBar() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-search", "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString,
        ]
        app.launch()
        NavigationTests.chooseMode("All", in: app)
        app.buttons["tab.browse"].tap()
        let input = app.searchFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        // Filters open in a sheet with Cancel and Apply in its bar.
        let filter = app.buttons["search.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        let apply = app.buttons["search.apply"]
        let cancel = app.buttons["search.cancelOptions"]
        XCTAssertTrue(apply.waitForExistence(timeout: 3))
        XCTAssertTrue(cancel.isHittable)
        app.segmentedControls["search.filters.mode"].buttons["Manga"].tap()
        screenshot("Search filters")
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 3))
        // Cancel discards a changed sort.
        filter.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        app.buttons["Title Z–A"].tap()
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 3))
        // Results arrive while typing, before the search is submitted, and keep the filter.
        input.tap()
        input.typeText("moon")
        XCTAssertTrue(app.buttons["search.result.moon"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.result.garden"].exists)
        XCTAssertLessThan(input.frame.maxY, app.buttons["search.result.moon"].frame.minY)
        input.typeText("\n")
        XCTAssertTrue(app.buttons["search.result.moon"].waitForExistence(timeout: 5))
        dismissKeyboard(app)
        screenshot("Search results")
        // Filters stay reachable while the search field is active.
        XCTAssertTrue(
            (filter.exists && filter.isHittable) || app.buttons["search.filter.inline"].isHittable)
        // Leaving the tab keeps the query and its results.
        app.buttons["tab.library"].tap()
        app.buttons["tab.browse"].tap()
        XCTAssertTrue(app.buttons["tab.browse"].isSelected)
        XCTAssertEqual(input.value as? String, "moon")
        XCTAssertTrue(app.buttons["search.result.moon"].waitForExistence(timeout: 3))
        // The applied Manga filter is kept either way.
        XCTAssertFalse(app.buttons["search.result.garden"].exists)
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        // Dragging the results dismisses the keyboard and keeps the search.
        let result = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'search.result.'")
        ).firstMatch
        if result.exists { result.swipeDown(velocity: .slow) }
        if app.keyboards.firstMatch.exists {
            app.visibleNavigationBar.buttons["Close"].tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

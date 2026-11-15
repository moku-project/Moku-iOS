import XCTest

@MainActor
final class SearchTests: XCTestCase {
    func testPopularGridFollowsContentButtonWithoutOpeningKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString]
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
            XCTAssertTrue(app.settingsIndex.exists || app.settingsIndex.waitForExistence(timeout: 1))
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
        XCTAssertTrue(app.staticTexts["Add a repository to find extensions"].waitForExistence(timeout: 10))
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
        app.launchArguments = ["--ui-testing-search", "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString]
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
        app.launchArguments = ["--ui-testing-search", "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString]
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
        XCTAssertTrue((filter.exists && filter.isHittable) || app.buttons["search.filter.inline"].isHittable)
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
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.result.'")).firstMatch
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

@MainActor
final class LiveSearchTests: XCTestCase {
    func testEmbeddedthe sourceSearch() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MOKU_LIVE_SEARCH"] == "1",
            "Set TEST_RUNNER_MOKU_LIVE_SEARCH=1 for this network integration test.")
        let app = XCUIApplication()
        app.launchArguments = ["-contentMode", "all", "--ui-testing-isolated-backend"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.browse"].waitForExistence(timeout: 15))
        app.openSettings()
        app.openSettingsRow("more.category.Extensions")
        let section = app.segmentedControls["extensions.section"]
        XCTAssertTrue(section.waitForExistence(timeout: 10))
        app.buttons["extensions.addRepository"].tap()
        let repositoryURL = app.textFields["extensions.repositoryURL"]
        XCTAssertTrue(repositoryURL.waitForExistence(timeout: 5))
        repositoryURL.tap()
        repositoryURL.typeText(
            "https://example.com/repo/index.pb")
        app.buttons["Add"].tap()
        XCTAssertTrue(repositoryURL.waitForNonExistence(timeout: 120))
        section.buttons["Browse"].tap()
        let catalogQuery = app.searchFields.firstMatch
        catalogQuery.tap()
        catalogQuery.typeText("the source")
        let install = app.buttons["extensions.install.example.source"]
        XCTAssertTrue(install.waitForExistence(timeout: 30))
        install.tap()
        // The page is disabled while the install runs.
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: section)
        waitForExpectations(timeout: 180)
        section.buttons["Installed"].tap()
        let source = app.buttons["extensions.search.example.source"]
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        source.press(forDuration: 1.0)
        app.buttons["Source Settings"].tap()
        XCTAssertTrue(app.navigationBars["the source"].waitForExistence(timeout: 10))
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

        // Forward fetching: the source lists Rent-A-Girlfriend, but its chapters were
        // removed, so a typed search should hide it once its chapters are checked.
        app.buttons["tab.browse"].tap()
        let input = app.searchFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("Rent a Girlfriend")
        input.typeText("\n")
        let results = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.result.'"))
        XCTAssertTrue(results.firstMatch.waitForExistence(timeout: 180))
        print("LIVE before:", results.allElementsBoundByIndex.map(\.label))
        capture("Live the source search, first results")
        let hidden = app.staticTexts["search.hiddenEmpty"]
        XCTAssertTrue(hidden.waitForExistence(timeout: 120), "No empty titles were hidden")
        Thread.sleep(forTimeInterval: 5)
        print("LIVE hidden note:", hidden.label)
        print("LIVE after:", results.allElementsBoundByIndex.map(\.label))
        capture("Live the source search, empty titles hidden")
        // Every title still listed must open with chapters.
        let kept = results.allElementsBoundByIndex.map(\.identifier)
        for id in kept {
            let row = app.buttons[id]
            guard row.exists else { continue }
            let title = row.label
            row.tap()
            XCTAssertTrue(app.descendants(matching: .any)["search.details"].waitForExistence(timeout: 30))
            // "Start reading" / "Continue" only appears when the title has chapters.
            let chapter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start' OR label BEGINSWITH 'Continue' OR label BEGINSWITH 'Read again'")).firstMatch
            let opened = chapter.waitForExistence(timeout: 60)
            print("LIVE kept:", title, "chapters shown:", opened, "empty notice:", app.otherElements["details.emptyChapters"].exists || app.staticTexts["details.emptyChapters"].exists)
            XCTAssertTrue(opened, "\(title) was kept but shows no chapters")
            capture("Live kept title: \(title)")
            app.goBack()
            XCTAssertTrue(input.waitForExistence(timeout: 10))
        }
        app.openTab("settings")
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        source.swipeLeft()
        app.buttons["Uninstall"].firstMatch.tap()
        app.buttons["Uninstall"].firstMatch.tap()
        // Uninstalled: the Installed list is empty again.
        XCTAssertTrue(app.descendants(matching: .any)["extensions.empty"].waitForExistence(timeout: 10))

    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

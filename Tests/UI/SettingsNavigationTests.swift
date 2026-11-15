import XCTest

@MainActor final class SettingsNavigationTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.fresh(["--ui-testing-search", "--ui-testing-isolated-backend"])
        app.launch()
        return app
    }

    func testSettingsPreferencesPersist() {
        let app = launch()
        app.openSettings()
        keepScreenshot("Settings sections")
        app.openSettingsRow("settings.category.General")
        XCTAssertTrue(app.staticTexts["Interface scale"].waitForExistence(timeout: 5))
        keepScreenshot("Settings general")
        app.goBack()
        app.openSettingsRow("settings.category.Appearance")
        let theme = app.buttons["settings.picker.App theme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 3))
        theme.tap()
        XCTAssertTrue(app.buttons["Sepia"].firstMatch.waitForExistence(timeout: 3))
        // The theme swatches below also carry the name; pick the menu's row.
        let sepia = app.buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@", "Sepia", "Sepia")).allElementsBoundByIndex
        (sepia.last(where: \.isHittable) ?? sepia.last!).tap()
        XCTAssertTrue(theme.shows("Sepia") || theme.shows("sepia"),
            "Theme picker should show Sepia: \(theme.label) / \(String(describing: theme.value))")
        keepScreenshot("Settings appearance")
        app.goBack()
        app.openSettingsRow("settings.category.Library")
        keepScreenshot("Settings library")
        let list = app.switches["List layout"]
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        list.flip()
        XCTAssertEqual(list.value as? String, "1")
        app.goBack()
        app.openSettingsRow("settings.category.Storage")
        XCTAssertTrue(app.buttons["Refresh storage usage"].waitForExistence(timeout: 5))
        keepScreenshot("Settings storage")
        app.goBack()
        app.terminate()
        app.launch()
        app.openSettings()
        app.openSettingsRow("settings.category.Library")
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertEqual(list.value as? String, "1")
    }

    /// Every settings category and Settings-tab destination opens as a pushed page
    /// with its title in the navigation bar and a working back button.
    func testEverySectionHasADestinationAndBackButton() {
        let app = launch()
        app.openSettings()
        let rows: [(String, String)] = [
            ("more.category.Extensions", "Extensions"), ("more.category.Tracking", "Tracking"),
            ("more.category.History", "History"),
        ] + [
            "General", "Appearance", "Reader", "Player", "Library", "Folders", "Content",
            "Automation", "Performance", "Keybinds", "Sync", "Storage", "Server", "Auth",
        ].map { ("settings.category.\($0)", $0) } + [
            ("settings.category.Tracking", "Tracker Accounts"), ("more.category.About", "About"),
            ("settings.category.Dev tools", "Dev tools"),
        ]
        for (id, title) in rows {
            app.openSettingsRow(id)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "No page titled \(title)")
            keepScreenshot("Settings \(title)")
            app.goBack()
            XCTAssertTrue(app.settingsIndex.waitForExistence(timeout: 3), "Back from \(title)")
        }
    }

    func testPlayerDefaultsAndKeyboardPreferencePersist() {
        let app = launch()
        app.openSettings()
        app.openSettingsRow("settings.category.Player")
        let autoplay = app.switches["Autoplay"]
        XCTAssertTrue(autoplay.waitForExistence(timeout: 5))
        autoplay.flip()
        XCTAssertEqual(autoplay.value as? String, "0")
        let speed = app.buttons["settings.picker.Playback speed"]
        speed.tap()
        app.buttons["1.5×"].tap()
        XCTAssertTrue(speed.shows("1.5×"), "\(speed.label) \(String(describing: speed.value))")
        app.goBack()
        app.openSettingsRow("settings.category.Keybinds")
        let play = app.buttons["settings.picker.Play or pause"]
        app.reveal(play, in: app.collectionViews["settings.scroll"])
        play.tap()
        app.buttons["K"].tap()
        XCTAssertEqual(play.value as? String, "k")
        app.terminate()
        app.launch()
        app.openSettings()
        app.openSettingsRow("settings.category.Player")
        XCTAssertTrue(autoplay.waitForExistence(timeout: 5))
        XCTAssertEqual(autoplay.value as? String, "0")
        XCTAssertTrue(speed.shows("1.5×"), "\(speed.label) \(String(describing: speed.value))")
        app.goBack()
        app.openSettingsRow("settings.category.Keybinds")
        app.reveal(play, in: app.collectionViews["settings.scroll"])
        XCTAssertEqual(play.value as? String, "k")
    }

    func testLiveAutomationAndContentSettingsSave() {
        let app = launch()
        app.openSettings()
        app.openSettingsRow("settings.category.Automation")
        let toggle = app.switches["Enable automation"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: toggle)
        waitForExpectations(timeout: 20)
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.flip()
        expectation(for: NSPredicate(format: "value == '0' AND enabled == true"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        app.goBack()
        app.openSettingsRow("settings.category.Automation")
        expectation(for: NSPredicate(format: "value == '0' AND enabled == true"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        keepScreenshot("Live automation settings")
        app.goBack()
        // Content: the server's content level and rules load live, and a change saves.
        app.openSettingsRow("settings.category.Content")
        let level = app.buttons["settings.picker.Content level"]
        XCTAssertTrue(level.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["gore"].waitForExistence(timeout: 10), "Rules should load")
        level.tap()
        let strict = app.buttons["Strict"].firstMatch
        XCTAssertTrue(strict.waitForExistence(timeout: 3))
        strict.tap()
        expectation(for: NSPredicate(format: "(label CONTAINS 'Strict' OR value CONTAINS 'Strict') AND enabled == true"), evaluatedWith: level)
        waitForExpectations(timeout: 10)
        app.goBack()
        app.openSettingsRow("settings.category.Content")
        expectation(for: NSPredicate(format: "label CONTAINS 'Strict' OR value CONTAINS 'Strict'"), evaluatedWith: level)
        waitForExpectations(timeout: 15)
        keepScreenshot("Live content settings")
    }

    /// Settings is a tab now: leaving it and coming back must not reset the page the
    /// user was on in another tab.
    func testSettingsTabKeepsOtherTabsState() {
        let app = XCUIApplication.fresh()
        app.launch()
        app.openTab("downloads")
        let tools = app.buttons["downloads.activeView"]
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.tap()
        menuItem(app, "downloads.history", "History").tap()
        let historyEmpty = app.staticTexts["Finished and removed downloads will appear here."]
        XCTAssertTrue(historyEmpty.waitForExistence(timeout: 5))
        app.openSettings()
        app.openSettingsRow("settings.category.General")
        XCTAssertTrue(app.navigationBars["General"].waitForExistence(timeout: 5))
        keepScreenshot("Settings general from Downloads")
        app.openTab("downloads")
        XCTAssertTrue(historyEmpty.waitForExistence(timeout: 3))
        // Settings keeps its own stack too.
        app.openTab("settings")
        XCTAssertTrue(app.navigationBars["General"].waitForExistence(timeout: 3))
        // Re-selecting the open tab pops to its root.
        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.settingsIndex.waitForExistence(timeout: 3))
    }

    private func menuItem(_ app: XCUIApplication, _ id: String, _ label: String) -> XCUIElement {
        let byID = app.buttons[id]
        if byID.waitForExistence(timeout: 2) { return byID }
        let byLabel = app.buttons[label].firstMatch
        XCTAssertTrue(byLabel.waitForExistence(timeout: 3), "Missing menu item \(label)")
        return byLabel
    }
}

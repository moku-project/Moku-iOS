import XCTest

@MainActor final class SettingsNavigationTests: XCTestCase {
    func testSettingsPreferencesPersist() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString, "--ui-testing-search", "--ui-testing-isolated-backend",
        ]
        app.launch()
        openSettings(app)
        capture("Settings sections")
        app.buttons["settings.category.General"].tap()
        XCTAssertTrue(app.staticTexts["Interface scale"].waitForExistence(timeout: 5))
        capture("Settings general")
        app.buttons["settings.back"].tap()
        app.buttons["settings.category.Appearance"].tap()
        XCTAssertTrue(app.buttons["settings.picker.App theme"].waitForExistence(timeout: 3))
        app.buttons["settings.picker.App theme"].tap()
        app.buttons["Sepia"].tap()
        XCTAssertEqual(app.buttons["settings.picker.App theme"].value as? String, "sepia")
        capture("Settings appearance")
        app.buttons["settings.back"].tap()
        app.buttons["settings.category.Library"].tap()
        capture("Settings library")
        app.switches["List layout"].tap()
        XCTAssertEqual(app.switches["List layout"].value as? String, "1")
        app.buttons["settings.back"].tap()
        app.buttons["settings.category.Storage"].tap()
        XCTAssertTrue(app.staticTexts["Storage usage"].waitForExistence(timeout: 3))
        capture("Settings storage")
        app.buttons["settings.back"].tap()
        app.buttons["account.back"].tap()
        app.terminate()
        app.launch()
        openSettings(app)
        app.buttons["settings.category.Library"].tap()
        XCTAssertEqual(app.switches["List layout"].value as? String, "1")
    }

    func testEveryDesktopSectionHasADestinationAndBackButton() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString, "--ui-testing-search", "--ui-testing-isolated-backend",
        ]
        app.launch()
        openSettings(app)
        for name in [
            "General", "Appearance", "Reader", "Player", "Library", "Automation", "Tracking",
            "Performance", "Keybinds", "Storage", "Folders", "Content", "Server", "Auth", "About",
            "Dev Tools",
        ] {
            let row = app.buttons["settings.category.\(name)"]
            for _ in 0..<4 {
                if row.isHittable && row.frame.maxY < app.frame.maxY - 130 { break }
                app.scrollViews["settings.index"].swipeUp()
            }
            XCTAssertTrue(row.isHittable, "Missing section: \(name)")
            row.tap()
            let back = app.buttons["settings.back"]
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts[name].exists)
            capture("Settings \(name)")
            back.tap()
            XCTAssertTrue(app.scrollViews["settings.index"].waitForExistence(timeout: 3))
        }
    }

    func testPlayerDefaultsAndKeyboardPreferencePersist() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString, "--ui-testing-search", "--ui-testing-isolated-backend",
        ]
        app.launch()
        openSettings(app)
        app.buttons["settings.category.Player"].tap()
        let autoplay = app.switches["Autoplay"]
        XCTAssertTrue(autoplay.waitForExistence(timeout: 5))
        autoplay.tap()
        XCTAssertEqual(autoplay.value as? String, "0")
        app.buttons["Playback speed"].tap()
        app.buttons["1.5×"].tap()
        XCTAssertEqual(app.buttons["Playback speed"].value as? String, "1.5×")
        app.buttons["settings.back"].tap()
        let keybinds = app.buttons["settings.category.Keybinds"]
        for _ in 0..<4 where !keybinds.isHittable { app.scrollViews["settings.index"].swipeUp() }
        keybinds.tap()
        for _ in 0..<6 where !app.buttons["settings.picker.Play or pause"].isHittable { app.scrollViews["settings.scroll"].swipeUp() }
        app.buttons["settings.picker.Play or pause"].tap()
        app.buttons["K"].tap()
        app.terminate()
        app.launch()
        openSettings(app)
        app.buttons["settings.category.Player"].tap()
        XCTAssertEqual(autoplay.value as? String, "0")
        XCTAssertEqual(app.buttons["Playback speed"].value as? String, "1.5×")
        app.buttons["settings.back"].tap()
        for _ in 0..<4 where !keybinds.isHittable { app.scrollViews["settings.index"].swipeUp() }
        keybinds.tap()
        for _ in 0..<6 where !app.buttons["settings.picker.Play or pause"].isHittable { app.scrollViews["settings.scroll"].swipeUp() }
        XCTAssertEqual(app.buttons["settings.picker.Play or pause"].value as? String, "k")
    }

    func testLiveAutomationAndContentSettingsSave() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString, "--ui-testing-search", "--ui-testing-isolated-backend"]
        app.launch()
        openSettings(app)
        app.buttons["settings.category.Automation"].tap()
        let toggle = app.switches["Enable automation"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: toggle)
        waitForExpectations(timeout: 20)
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        expectation(for: NSPredicate(format: "value == '0' AND enabled == true"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        app.buttons["settings.back"].tap()
        app.buttons["settings.category.Automation"].tap()
        expectation(for: NSPredicate(format: "value == '0' AND enabled == true"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        capture("Live automation settings")
        app.buttons["settings.back"].tap()
        let content = app.buttons["settings.category.Content"]
        for _ in 0..<5 where !content.isHittable { app.scrollViews["settings.index"].swipeUp() }
        content.tap()
        let overrides = app.switches["Per-source overrides"]
        XCTAssertTrue(overrides.waitForExistence(timeout: 10))
        expectation(for: ready, evaluatedWith: overrides)
        waitForExpectations(timeout: 10)
        overrides.tap()
        expectation(for: NSPredicate(format: "value == '1' AND enabled == true"), evaluatedWith: overrides)
        waitForExpectations(timeout: 10)
        capture("Live content settings")
    }

    func testAccountPagesReturnToOriginAndNestedSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString]
        app.launch()
        app.buttons["Downloads"].tap()
        app.buttons["downloads.history"].tap()
        app.buttons["Settings"].firstMatch.tap()
        let back = app.buttons["account.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        XCTAssertEqual(back.label, "Back to Downloads")
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label == %@", "Open profile"))
                .allElementsBoundByIndex.contains { $0.isHittable })
        capture("Settings spacious index")
        back.tap()
        XCTAssertTrue(app.buttons["downloads.history"].isSelected)
        XCTAssertFalse(app.buttons["header.profile"].exists)
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["settings.category.General"].tap()
        app.buttons["settings.back"].tap()
        back.tap()
        XCTAssertTrue(app.buttons["downloads.history"].isSelected)
    }

    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 5))
        app.buttons["tab.home"].tap()
        let settings = app.buttons.matching(identifier: "header.settings").allElementsBoundByIndex
            .first(where: \.isHittable)
        XCTAssertNotNil(settings)
        settings?.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

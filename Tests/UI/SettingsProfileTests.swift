import XCTest

@MainActor final class SettingsProfileTests: XCTestCase {
    func testSettingsAndProfileIsolation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-profiles", "-mokuProfileTestID", UUID().uuidString]
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        capture("Settings sections")
        app.buttons["settings.category.General"].tap()
        XCTAssertTrue(
            app.buttons["settings.picker.Preferred source language"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["Cover cache"].waitForExistence(timeout: 3))
        capture("Settings storage")
        app.buttons["settings.back"].tap()
        app.buttons["account.back"].tap()
        app.buttons["Open profile"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Add profile"].waitForExistence(timeout: 3))
        capture("Profile")
        app.buttons["Add profile"].tap()
        let name = app.textFields["profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Second")
        app.buttons["Save"].tap()
        let second = app.buttons["Switch to Second"]
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        second.tap()
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["settings.category.Library"].tap()
        XCTAssertEqual(app.switches["List layout"].value as? String, "0")
        app.terminate()
        app.launch()
        app.buttons["Open profile"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Switch to Second"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Switch to Second"].isSelected)
    }

    func testEveryDesktopSectionHasADestinationAndBackButton() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-profiles", "-mokuProfileTestID", UUID().uuidString]
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
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
            if name == "Reader" { capture("Settings reserved section") }
            back.tap()
            XCTAssertTrue(app.scrollViews["settings.index"].waitForExistence(timeout: 3))
        }
    }

    func testAccountPagesReturnToOriginAndNestedSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-profiles", "-mokuProfileTestID", UUID().uuidString]
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
        app.buttons["Open profile"].firstMatch.tap()
        XCTAssertEqual(back.label, "Back to Downloads")
        capture("Profile back header")
        back.tap()
        XCTAssertTrue(app.buttons["downloads.history"].isSelected)
        app.buttons["Settings"].firstMatch.tap()
        let auth = app.buttons["settings.category.Auth"]
        for _ in 0..<6 {
            if auth.isHittable && auth.frame.maxY < app.frame.maxY - 130 { break }
            app.scrollViews["settings.index"].swipeUp()
        }
        auth.tap()
        app.buttons["Manage local profiles"].tap()
        XCTAssertEqual(back.label, "Back to Settings")
        back.tap()
        XCTAssertTrue(app.buttons["Manage local profiles"].waitForExistence(timeout: 3))
        app.buttons["settings.back"].tap()
        back.tap()
        XCTAssertTrue(app.buttons["downloads.history"].isSelected)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

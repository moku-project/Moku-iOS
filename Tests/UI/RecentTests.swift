import XCTest

@MainActor final class RecentUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-storage", "--ui-testing-home-populated", "--ui-testing-recent",
            "-mokuStorageTestID", UUID().uuidString,
        ]
        app.launch()
        app.openSettings()
        app.openSettingsRow("more.category.History")
        XCTAssertTrue(app.segmentedControls["recent.activeView"].waitForExistence(timeout: 5))
        return app
    }

    func testHistorySearchExpansionUpdatesAndModes() {
        let app = launch()
        let row = app.buttons["Resume I’m Not That Kind of Talent"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        capture("Recent history")
        // Row actions live in the context menu.
        row.press(forDuration: 1.0)
        app.buttons["Show Chapters"].firstMatch.tap()
        row.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Hide Chapters"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Clear Title History"].firstMatch.exists)
        capture("Recent expanded history")
        app.buttons["Hide Chapters"].firstMatch.tap()
        // The system search field filters history.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("No matching fixture")
        XCTAssertTrue(app.staticTexts["No Results for “No matching fixture”"].waitForExistence(timeout: 3)
            || app.staticTexts["No Results"].waitForExistence(timeout: 1))
        XCTAssertFalse(row.exists)
        // Clearing the query brings the history back.
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 24))
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        // Leave the search field so the view picker returns to the bar.
        let close = app.visibleNavigationBar.buttons["Close"]
        if close.exists { close.tap() }
        app.segmentedControls["recent.activeView"].buttons["Updates"].tap()
        let expand = app.buttons["Expand I’m Not That Kind of Talent updates"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        expand.tap()
        let download = app.buttons["Download Chapter 14"]
        XCTAssertTrue(download.waitForExistence(timeout: 3))
        capture("Recent updates")
        download.tap()
        XCTAssertTrue(app.buttons["Download queued"].firstMatch.waitForExistence(timeout: 3))
        // The type filter is in the toolbar menu.
        app.menuItem(app.buttons["recent.tools"], "Anime").tap()
        XCTAssertFalse(expand.exists)
        let anime = app.buttons["Expand Monster But Wild updates"]
        XCTAssertTrue(anime.waitForExistence(timeout: 3))
        anime.tap()
        XCTAssertTrue(app.buttons["Open Episode 12"].waitForExistence(timeout: 3))
        capture("Recent anime updates")
        app.menuItem(app.buttons["recent.tools"], "Check for Updates").tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
        app.alerts.buttons["OK"].tap()
    }

    func testClearHistoryRequiresConfirmation() {
        let app = launch()
        let row = app.buttons["Resume I’m Not That Kind of Talent"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.menuItem(app.buttons["recent.tools"], "Clear All History").tap()
        let confirm = app.buttons["recent.confirmClear"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        // Dismiss without clearing.
        // From a toolbar menu the dialog is a popover with no Cancel button: tap outside it.
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() } else {
            app.otherElements["PopoverDismissRegion"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        }
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 3))
        XCTAssertTrue(row.exists)
        app.menuItem(app.buttons["recent.tools"], "Clear All History").tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        app.buttons.matching(identifier: "recent.confirmClear").allElementsBoundByIndex
            .last(where: \.isHittable)?.tap()
        XCTAssertTrue(app.staticTexts["No History Yet"].waitForExistence(timeout: 5))
        capture("Recent empty history")
    }

    private func capture(_ name: String) { keepScreenshot(name) }
}

@MainActor final class TrackingUITests: XCTestCase {
    func testServicesMenusAndDisconnectConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-storage", "--ui-testing-tracking",
            "-mokuStorageTestID", UUID().uuidString,
        ]
        app.launch()
        app.openSettings()
        app.openSettingsRow("more.category.Tracking")
        let anilist = app.buttons["tracking.service.anilist"]
        XCTAssertTrue(anilist.waitForExistence(timeout: 5))
        XCTAssertTrue(anilist.label.contains("Connected"), anilist.label)
        // Trackers the server can't sign in to are hidden rather than shown as "Coming soon".
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Coming soon'")).firstMatch.exists)
        keepScreenshot("Tracking services")
        app.buttons["tracking.fab"].tap()
        let importAction = app.buttons["tracking.action.Import list"].waitForExistence(timeout: 2)
            ? app.buttons["tracking.action.Import list"] : app.buttons["Import List…"].firstMatch
        XCTAssertTrue(importAction.waitForExistence(timeout: 3))
        keepScreenshot("Tracking actions menu")
        importAction.tap()
        if app.buttons["AniList"].waitForExistence(timeout: 2) { app.buttons["AniList"].tap() }
        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        keepScreenshot("Tracking import setup")
        next.tap()
        let start = app.buttons["Import 1"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        keepScreenshot("Tracking import review")
        start.tap()
        // The fixture import finishes at once, so check the row's final state rather than the progress text.
        XCTAssertTrue(app.staticTexts["Imported"].waitForExistence(timeout: 5))
        app.buttons["Save & Close"].tap()
        XCTAssertTrue(app.buttons["Save & Close"].waitForNonExistence(timeout: 5))
        // Disconnecting asks first; dismissing the dialog keeps the account.
        openDisconnect(app, anilist)
        XCTAssertTrue(app.buttons.matching(identifier: "Disconnect").firstMatch.waitForExistence(timeout: 3))
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
        XCTAssertTrue(anilist.waitForExistence(timeout: 3))
        XCTAssertTrue(anilist.label.contains("Connected"), anilist.label)
        openDisconnect(app, anilist)
        let confirm = app.buttons["Disconnect"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'Not connected'"), evaluatedWith: anilist)
        waitForExpectations(timeout: 5)
        // A disconnected service can still connect with a pasted token.
        let useToken = app.buttons["Use a Token"].firstMatch
        for _ in 0..<2 where !useToken.exists {
            anilist.press(forDuration: 1.2)
            _ = useToken.waitForExistence(timeout: 2)
        }
        useToken.tap()
        XCTAssertTrue(app.secureTextFields["tracking.token"].waitForExistence(timeout: 3)
            || app.textFields["tracking.token"].waitForExistence(timeout: 1))
        app.buttons["Cancel"].firstMatch.tap()
    }

    /// Starts a disconnect from the row's swipe action, or its context menu.
    private func openDisconnect(_ app: XCUIApplication, _ row: XCUIElement) {
        let action = app.buttons["Disconnect"].firstMatch
        row.swipeLeft()
        if !action.waitForExistence(timeout: 2) {
            row.press(forDuration: 1.2)
            XCTAssertTrue(action.waitForExistence(timeout: 3), "No Disconnect action")
        }
        action.tap()
    }
}

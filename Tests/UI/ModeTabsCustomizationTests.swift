import XCTest

/// The per-page mode tabs and their customization popover were removed with the
/// native tab bar; a saved mode configuration still decides what the content button offers.
@MainActor final class ModeTabsCustomizationTests: XCTestCase {
    func testSavedModeOrderAndHiddenModesDriveTheContentButton() {
        let app = XCUIApplication.fresh([
            "--ui-testing-isolated-backend", "--ui-testing-search", "--ui-testing-extensions",
            // Launch arguments are parsed as property lists: quote the JSON so it stays a string.
            "-preferences.modeTabs",
            #""{\"order\":[\"all\",\"anime\",\"novels\",\"manga\"],\"hidden\":[\"manga\"]}""#,
        ])
        app.launch()
        let mode = app.buttons["mode.button"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        XCTAssertEqual(mode.value as? String, "All")
        // Tapping follows the saved order and skips the hidden type.
        for title in ["Anime", "Novels", "All"] {
            mode.tap()
            expectation(for: NSPredicate(format: "value == %@", title), evaluatedWith: mode)
            waitForExpectations(timeout: 3)
        }
        mode.press(forDuration: 0.8)
        let anime =
            app.buttons["mode.anime"].waitForExistence(timeout: 2)
            ? app.buttons["mode.anime"] : app.buttons["Anime"].firstMatch
        XCTAssertTrue(anime.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Manga"].exists)
        XCTAssertFalse(app.buttons["mode.manga"].exists)
        let novels =
            app.buttons["mode.novels"].exists
            ? app.buttons["mode.novels"] : app.buttons["Novels"].firstMatch
        XCTAssertLessThan(anime.frame.midY, novels.frame.midY)
        keepScreenshot("Content menu with saved order")
        anime.tap()
        XCTAssertEqual(mode.value as? String, "Anime")
    }
}

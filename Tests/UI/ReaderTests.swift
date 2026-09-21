import XCTest

@MainActor final class ReaderUITests: XCTestCase {
    func testReaderDrawerNavigationAndSavedPreset() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reader"]
        app.launch()
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["reader.page"].exists)
        capture("reader-reading")
        app.buttons["reader.settings"].tap()
        // XCTest can report idle before SwiftUI’s trailing move transition finishes.
        Thread.sleep(forTimeInterval: 0.35)
        XCTAssertTrue(app.buttons["reader.drawer.close"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["reader.option.longstrip"].exists)
        capture("reader-settings-layout")
        app.buttons["reader.option.single"].tap()
        app.buttons["reader.option.rtl"].tap()
        app.buttons["reader.drawer.close"].tap()
        app.buttons["reader.previous"].tap()
        XCTAssertTrue(app.buttons["reader.page"].label.contains("2 / 12"))
        app.buttons["reader.bookmark"].tap()
        app.buttons["reader.settings"].tap()
        // XCTest can report idle before SwiftUI’s trailing move transition finishes.
        Thread.sleep(forTimeInterval: 0.35)
        let scroll = app.scrollViews["reader.drawer.scroll"]
        scroll.swipeUp()
        let save = app.buttons["reader.savePreset"]
        if !save.isHittable { scroll.swipeUp() }
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        capture("reader-settings-presets")
        save.tap()
        app.alerts.textFields.firstMatch.typeText("Manga")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Rename Manga"].waitForExistence(timeout: 3))
        app.terminate()
        app.launchArguments = ["--ui-testing-reader", "--reader-keep-preferences"]
        app.launch()
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["reader.page"].label.contains("2 / 12"))
        app.buttons["reader.settings"].tap()
        // XCTest can report idle before SwiftUI’s trailing move transition finishes.
        Thread.sleep(forTimeInterval: 0.35)
        XCTAssertTrue(app.buttons["reader.option.single"].isSelected)
    }
    func testLandscapeDrawerAndChapterPicker() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reader"]
        app.launch()
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: 10))
        app.buttons["reader.settings"].tap()
        // XCTest can report idle before SwiftUI’s trailing move transition finishes.
        Thread.sleep(forTimeInterval: 0.35)
        app.buttons["reader.option.double"].tap()
        XCTAssertTrue(app.buttons["reader.option.double"].isSelected)
        XCTAssertTrue(app.switches["Offset spreads"].waitForExistence(timeout: 3))
        capture("reader-landscape-drawer")
        app.buttons["reader.drawer.close"].tap()
        app.buttons["reader.chapters"].tap()
        XCTAssertTrue(app.textFields["Filter chapters"].waitForExistence(timeout: 3))
        app.textFields["Filter chapters"].tap()
        app.textFields["Filter chapters"].typeText("14")
        app.buttons.containing(.staticText, identifier: "Chapter 14").firstMatch.tap()
        XCTAssertTrue(app.buttons["reader.chapters"].waitForExistence(timeout: 3))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

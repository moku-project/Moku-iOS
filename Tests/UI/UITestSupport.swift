import XCTest

/// Shared steps for driving the native shell: the Moku tab bar, navigation-bar back
/// buttons, and the Settings tab's list.
@MainActor extension XCUIApplication {
    /// A launch on a fresh, isolated profile so settings from earlier runs can't leak in.
    static func fresh(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-storage", "-mokuStorageTestID", UUID().uuidString] + arguments
        return app
    }

    /// Selects a tab in the Moku tab bar (`home`, `browse`, `library`, `downloads`, `settings`).
    func openTab(_ tab: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = buttons["tab.\(tab)"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing tab \(tab)", file: file, line: line)
        button.tap()
    }

    /// The Settings tab's root list.
    var settingsIndex: XCUIElement { collectionViews["settings.index"] }

    /// Opens the Settings tab at its root.
    func openSettings(file: StaticString = #filePath, line: UInt = #line) {
        openTab("settings", file: file, line: line)
        if !settingsIndex.waitForExistence(timeout: 2) {
            // Re-selecting the open tab returns it to its first page.
            buttons["tab.settings"].tap()
        }
        XCTAssertTrue(settingsIndex.waitForExistence(timeout: 5), file: file, line: line)
    }

    /// Scrolls the Settings index until `identifier` is comfortably on screen, then taps it.
    func openSettingsRow(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = buttons[identifier]
        // Lazy lists only hold rows near the screen, so scroll before judging.
        _ = settingsIndex.waitForExistence(timeout: 5)
        if !row.waitForExistence(timeout: 1) || !row.isHittable { reveal(row, in: settingsIndex) }
        XCTAssertTrue(row.isHittable, "Row not reachable: \(identifier)", file: file, line: line)
        row.tap()
    }

    /// Scrolls `container` until `element` sits between the navigation bar and the
    /// floating tab bar, choosing the direction from where the element is.
    func reveal(_ element: XCUIElement, in container: XCUIElement) {
        let bottom = buttons["tab.home"].exists ? buttons["tab.home"].frame.minY - 8 : frame.maxY - 100
        var misses = 0
        for _ in 0..<12 {
            let bar = visibleNavigationBar
        let top = bar.exists ? bar.frame.maxY : frame.minY + 100
            guard element.exists else {
                // Lazy lists drop off-screen rows: look below first, then above.
                misses += 1
                if misses <= 4 { container.swipeUp(velocity: .slow) } else { container.swipeDown() }
                continue
            }
            let box = element.frame
            if box.minY < top { container.swipeDown(velocity: .slow) }
            else if box.maxY > bottom { container.swipeUp(velocity: .slow) }
            else if element.isHittable { return }
            else { container.swipeUp(velocity: .slow) }
        }
    }

    /// The navigation bar on screen. Every visited tab keeps its stack in the
    /// hierarchy, so `navigationBars.firstMatch` can be another tab's bar.
    var visibleNavigationBar: XCUIElement {
        let bars = navigationBars.allElementsBoundByIndex
        return bars.last(where: { $0.isHittable }) ?? navigationBars.firstMatch
    }

    /// The system back button of the visible navigation bar.
    var backButton: XCUIElement {
        let bar = visibleNavigationBar
        return bar.buttons["BackButton"]
    }

    func goBack(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(navigationBars.firstMatch.waitForExistence(timeout: 5), file: file, line: line)
        // An active search field takes over the bar; close it to get the back button.
        let close = visibleNavigationBar.buttons["Close"]
        if !visibleNavigationBar.buttons["BackButton"].exists, close.exists { close.tap() }
        let back = visibleNavigationBar.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 3), "No back button", file: file, line: line)
        back.tap()
    }
}

@MainActor extension XCTestCase {
    func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor extension XCUIElement {
    /// Flips a SwiftUI Toggle row by its switch, not its label.
    func flip() {
        let inner = switches.firstMatch
        if inner.exists { inner.tap() } else {
            coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
    }
}

@MainActor extension XCUIElement {
    /// Whether a picker row shows `text`, in its label or its value.
    func shows(_ text: String) -> Bool {
        label.contains(text) || ((value as? String)?.contains(text) ?? false)
    }
}

@MainActor extension XCUIApplication {
    /// Opens a toolbar Menu and returns its item labelled `label`, tapping again if the
    /// first tap landed while a dialog or menu was still animating away.
    func menuItem(_ menu: XCUIElement, _ label: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let item = buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label)).firstMatch
        for _ in 0..<3 {
            menu.tap()
            if item.waitForExistence(timeout: 2) { return item }
        }
        XCTFail("Menu item \(label) never appeared", file: file, line: line)
        return item
    }
}

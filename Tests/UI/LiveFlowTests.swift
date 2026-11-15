import XCTest

/// A new user's path on the real core: add a repository, install a source, read, save and download.
/// Opt in with TEST_RUNNER_MOKU_LIVE_REPOSITORY, _LIVE_EXTENSION (package) and _LIVE_SOURCE (catalog name).
@MainActor final class LiveFlowTests: XCTestCase {
    private var repository = ""
    private var package = ""
    private var sourceName = ""
    private var app: XCUIApplication!

    override func setUp() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let repository = env["MOKU_LIVE_REPOSITORY"], let package = env["MOKU_LIVE_EXTENSION"],
            let sourceName = env["MOKU_LIVE_SOURCE"]
        else { throw XCTSkip("Opt-in live flow against a real repository.") }
        (self.repository, self.package, self.sourceName) = (repository, package, sourceName)
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--acceptance", "--ui-testing-isolated-backend", "--ui-testing-start-runtime"]
        app.launch()
    }

    private func shot(_ name: String) {
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = name
        capture.lifetime = .keepAlways
        add(capture)
    }

    private func wait(_ element: XCUIElement, _ timeout: TimeInterval = 20, _ what: String) {
        if !element.waitForExistence(timeout: timeout) {
            shot("missing-\(what)")
            XCTFail("Not found: \(what)")
        }
    }

    private func firstMatch(_ prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    func testNewUserReadsAndDownloads() throws {
        // The bar: five tabs and the content button.
        wait(app.buttons["tab.settings"], 20, "tab bar")
        shot("01-launch")
        let modeButton = app.buttons["mode.button"]
        wait(modeButton, 5, "content button")
        let before = modeButton.value as? String
        modeButton.tap()
        XCTAssertNotEqual(modeButton.value as? String, before, "content button did not change type")
        shot("02-mode-tapped")
        while (modeButton.value as? String) != "All" { modeButton.tap() }

        // Settings → Extensions → add the repository.
        app.buttons["tab.settings"].tap()
        app.buttons["more.category.Extensions"].tap()
        wait(app.navigationBars["Extensions"], 10, "extensions page")
        shot("03-extensions")
        app.buttons["extensions.addRepository"].tap()
        let url = app.textFields["extensions.repositoryURL"]
        wait(url, 10, "repository field")
        url.tap()
        url.typeText(repository)
        app.navigationBars["Add Repository"].buttons["Add"].tap()
        // The sheet closes once the repository is saved.
        let sheetGone = expectation(for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.navigationBars["Add Repository"])
        wait(for: [sheetGone], timeout: 60)
        shot("04-repository-added")

        // Browse → find the source → install.
        app.segmentedControls.buttons["Browse"].tap()
        let search = app.searchFields.firstMatch
        wait(search, 10, "extensions search field")
        search.tap()
        search.typeText(sourceName + "\n")
        let install = app.buttons["extensions.install.\(package)"]
        wait(install, 60, "install button")
        shot("05-catalog")
        install.tap()

        // Installed shows it once the runtime has loaded it.
        app.segmentedControls.buttons["Installed"].tap()
        let source = app.buttons["extensions.search.\(package)"]
        wait(source, 300, "installed source")
        shot("06-installed")

        // Browse the source and open the first title.
        source.tap()
        let card = firstMatch("source.item.")
        wait(card, 90, "a title from the source")
        shot("07-source-browse")
        card.tap()

        // Details: chapters load; save the title.
        let chapter = firstMatch("details.chapter.")
        wait(chapter, 90, "a chapter")
        shot("08-details")
        let save = app.buttons["details.library"]
        wait(save, 5, "save button")
        save.tap()
        shot("09-saved")

        // Read the first chapter, then close the reader.
        chapter.tap()
        wait(firstMatch("reader."), 30, "reader")
        sleep(8)
        shot("10-reader")
        let close = app.buttons["reader.close"]
        if !close.exists { app.tap() }
        wait(close, 10, "reader close")
        close.tap()

        // Download a chapter from its swipe actions.
        wait(chapter, 20, "chapter after reader")
        chapter.swipeLeft()
        shot("11-chapter-swipe")
        let download = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Download'")).firstMatch
        wait(download, 5, "download swipe action")
        download.tap()

        // Library lists the saved title.
        app.buttons["tab.library"].tap()
        wait(firstMatch("library.item."), 20, "saved title in Library")
        shot("12-library")

        // Downloads shows the chapter.
        app.buttons["tab.downloads"].tap()
        sleep(5)
        shot("13-downloads")
        XCTAssertFalse(app.otherElements["downloads.empty"].exists && app.staticTexts["No Downloads"].exists,
            "Downloads is empty after downloading a chapter")

        // Search across sources.
        app.buttons["tab.browse"].tap()
        let searchField = app.searchFields.firstMatch
        wait(searchField, 10, "search field")
        searchField.tap()
        searchField.typeText("one\n")
        wait(firstMatch("search.result."), 90, "search results")
        shot("14-search")
    }
}

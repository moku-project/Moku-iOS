import XCTest

@MainActor
final class PlayerUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func testPlaybackPortraitLandscapeAndMenus() {
        let app = XCUIApplication()
        // Saved player settings outlive each launch and win over the fixture: start paused at 100%.
        app.launchArguments = ["--ui-testing-player", "-player.autoplay", "NO", "-player.subtitleScale", "1"]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        orient(.portrait, app: app)
        if !app.buttons["player.play"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let play = app.buttons["player.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: play)
        waitForExpectations(timeout: 10)
        play.tap()
        XCTAssertEqual(play.label, "Pause")
        play.tap()
        XCTAssertEqual(play.label, "Play")
        XCTAssertFalse(app.buttons["player.previous"].isEnabled)
        XCTAssertGreaterThanOrEqual(play.frame.height, 44)
        XCTAssertGreaterThanOrEqual(play.frame.width, 44)
        app.buttons["player.subtitles"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(
            app.staticTexts["A quiet moment before the journey."].waitForExistence(timeout: 5))
        app.buttons["Increase Size"].tap()
        XCTAssertTrue(app.staticTexts["110%"].exists)
        capture("Player portrait subtitles")
        app.buttons["player.panel.close"].tap()
        app.buttons["player.speed"].tap()
        app.buttons["1.5×"].tap()
        XCTAssertEqual(app.buttons["player.speed"].value as? String, "1.5 times")
        app.buttons["player.mute"].tap()
        XCTAssertEqual(app.buttons["player.mute"].label, "Unmute")
        app.sliders["player.timeline"].adjust(toNormalizedSliderPosition: 0.5)
        orient(.landscapeLeft, app: app)
        XCTAssertTrue(app.buttons["player.close"].waitForExistence(timeout: 5))
        app.buttons["player.subtitles"].tap()
        XCTAssertTrue(app.buttons["English"].isHittable)
        capture("Player landscape subtitles")
        app.buttons["player.panel.close"].tap()
        capture("Player landscape playback")
        app.buttons["player.next"].tap()
        XCTAssertTrue(app.staticTexts["Ep. 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["player.previous"].isEnabled)
        app.buttons["player.close"].tap()
        XCTAssertTrue(app.staticTexts["Player closed"].waitForExistence(timeout: 5))
    }

    /// Starts the same JVM/Go runtime as source playback and serves media over
    /// authenticated HTTP. Physical coordinate gestures exercise hit testing,
    /// unlike accessibility-only slider adjustments on a local file.
    func testStreamingSeeksAndTouchControlsWithEmbeddedRuntime() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-player", "--ui-testing-player-streaming",
            "--ui-testing-player-signals", "--ui-testing-isolated-backend",
            "-player.autoplay", "NO", "-player.subtitleScale", "1",
        ]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        let play = app.buttons["player.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 60), app.debugDescription)
        orient(.portrait, app: app)
        let slider = app.sliders["player.timeline"]
        waitFor(slider, "enabled == true")
        waitFor(slider, "value BEGINSWITH '0:08'")

        // Drag the actual thumb forwards and backwards while paused. Assert
        // AVPlayer's settled time, not just the value set by the drag callback.
        drag(slider, from: 8.0 / 24, to: 0.7)
        waitFor(slider, "value BEGINSWITH '0:16' OR value BEGINSWITH '0:17'")
        tap(app.buttons["player.mute"])
        XCTAssertEqual(app.buttons["player.mute"].label, "Unmute")
        drag(slider, from: 0.7, to: 0.25)
        waitFor(slider, "value BEGINSWITH '0:05' OR value BEGINSWITH '0:06'")
        XCTAssertEqual(play.label, "Play")
        tap(play)
        waitFor(play, "label == 'Pause'")
        waitFor(slider, "value BEGINSWITH '0:07' OR value BEGINSWITH '0:08'")
        tap(play)
        waitFor(play, "label == 'Play'")

        tap(app.buttons["player.speed"])
        tap(app.buttons["1.5×"])
        XCTAssertEqual(app.buttons["player.speed"].value as? String, "1.5 times")
        tap(app.buttons["player.options"])
        tap(app.buttons["Fixture B"])
        waitFor(slider, "enabled == true")
        XCTAssertEqual(play.label, "Play", "Changing source must preserve pause")
        tap(app.buttons["player.subtitles"])
        tap(app.buttons["English"])
        XCTAssertTrue(
            app.staticTexts["A quiet moment before the journey."].waitForExistence(timeout: 5))
        tap(app.buttons["Increase Size"])
        XCTAssertTrue(app.staticTexts["110%"].exists)
        tap(app.buttons["player.panel.close"])

        // Tap the video to hide/reveal; an overlay must not steal button taps.
        let video = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        video.tap()
        waitFor(play, "exists == false")
        video.tap()
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        orient(.landscapeLeft, app: app)
        waitFor(play, "hittable == true")
        tap(play)
        waitFor(play, "label == 'Pause'")
        // Starting point is the current thumb, read from the accessible time.
        let value = slider.value as? String ?? "0:08 of 0:24"
        let time = value.components(separatedBy: " of ")[0].split(separator: ":")
        let seconds = (Double(time.first ?? "0") ?? 0) * 60 + (Double(time.last ?? "0") ?? 0)
        drag(slider, from: seconds / 24, to: 0.15)
        tap(play)
        waitFor(play, "label == 'Play'")
        // Playback advances while XCTest delivers the drag and pause. Assert
        // the settled backward seek, allowing that real elapsed playback time.
        let settled = slider.value as? String ?? ""
        let fields = settled.components(separatedBy: " of ")[0].split(separator: ":")
        XCTAssertEqual(fields.count, 2)
        let settledSeconds =
            (Double(fields.first ?? "99") ?? 99) * 60
            + (Double(fields.last ?? "99") ?? 99)
        XCTAssertGreaterThan(settledSeconds, 0)
        XCTAssertLessThan(settledSeconds, 10)
        tap(app.buttons["player.next"])
        XCTAssertTrue(app.staticTexts["Ep. 2"].waitForExistence(timeout: 10))
        waitFor(slider, "enabled == true")
        tap(app.buttons["player.previous"])
        XCTAssertTrue(app.staticTexts["Ep. 1"].waitForExistence(timeout: 10))
        tap(app.buttons["player.episodes"])
        tap(app.buttons["Ep. 3 — Episode 3"])
        XCTAssertTrue(app.staticTexts["Ep. 3"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["player.next"].isEnabled)
        tap(app.buttons["player.close"])
        XCTAssertTrue(app.staticTexts["Player closed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func orient(_ orientation: UIDeviceOrientation, app: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        var previous: CGRect?
        let stable = NSPredicate { _, _ in
            let frame = app.frame
            let matches =
                orientation == .portrait ? frame.height > frame.width : frame.width > frame.height
            defer { previous = frame }
            return matches && previous == frame
        }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: stable, object: app)
                ], timeout: 10), .completed)
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertTrue(element.isHittable)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func drag(_ slider: XCUIElement, from: Double, to: Double) {
        // UISlider thumb centers are inset by half the custom 12-point thumb.
        let usable = slider.frame.width - 12
        let start = slider.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 6 + usable * from, dy: slider.frame.height / 2))
        let end = slider.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 6 + usable * to, dy: slider.frame.height / 2))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func waitFor(
        _ element: XCUIElement, _ predicate: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let result = XCTWaiter.wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: predicate), object: element)
            ], timeout: 10)
        XCTAssertEqual(
            result, .completed, "\(predicate): \(element.debugDescription)", file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

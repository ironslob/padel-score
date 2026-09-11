import XCTest

/// Drives one game from 0–0 for the marketing site clip.
/// Run via `website/scripts/record-score-demo.sh`.
///
/// Same-side points wait out the undo window so the countdown ring is visible.
/// After 30–0 the test taps Them, then taps Them again to undo, then continues
/// 30–15 → 40–15 → Game. t0/t1 timestamps let the encode script trim simulator
/// video to the scoring sequence (keeping the ring’s in-between frames).
final class MarketingDemoTests: XCTestCase {
    private let recordStartedAt = "/tmp/wr-demo-t0"
    private let recordEndedAt = "/tmp/wr-demo-t1"

    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Health access") { alert in
            if alert.buttons["Close"].exists {
                alert.buttons["Close"].tap()
                return true
            }
            return false
        }
    }

    func testScoreDemo() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasSeenWristRaiseTip", "YES",
            "-warmUpEnabled", "NO",
        ]
        app.launch()

        tapIfExists(app.buttons["Got it"], timeout: 1.5)
        dismissHealthSheetIfNeeded()

        if app.staticTexts["Who's serving?"].waitForExistence(timeout: 0.6) {
            app.buttons["Back"].tap()
            pause(0.3)
        }

        XCTAssertTrue(
            app.buttons["Start Match"].waitForExistence(timeout: 8),
            app.debugDescription
        )
        app.buttons["Start Match"].tap()
        dismissHealthSheetIfNeeded()
        tapIfExists(app.buttons["Track without workout"], timeout: 1.5)
        tapIfExists(app.buttons["OK"], timeout: 0.8)
        dismissHealthSheetIfNeeded()

        if app.staticTexts["Who's serving?"].waitForExistence(timeout: 8) {
            pause(0.25)
            let usServe = app.buttons["We are serving"]
            XCTAssertTrue(usServe.waitForExistence(timeout: 2), app.debugDescription)
            usServe.tap()
            dismissHealthSheetIfNeeded()
        }

        waitForScore(app, prefix: "Us", score: "0")
        beginRecording()
        pause(1.5)

        tapSide(app, prefix: "Us") // 15–0
        waitForScore(app, prefix: "Us", score: "15")
        pause(3.15)

        tapSide(app, prefix: "Us") // 30–0
        waitForScore(app, prefix: "Us", score: "30")
        pause(1.4)

        tapSide(app, prefix: "Them") // 30–15, then undo while the ring is still running
        pause(1.2)
        tapSide(app, prefix: "Them")
        waitForScore(app, prefix: "Them", score: "0")
        pause(1.4)

        tapSide(app, prefix: "Them") // 30–15
        waitForScore(app, prefix: "Them", score: "15")
        pause(1.4)

        tapSide(app, prefix: "Us") // 40–15
        waitForScore(app, prefix: "Us", score: "40")
        pause(3.15)

        tapSide(app, prefix: "Us") // Game
        let next = app.buttons["Next"]
        let nextDeadline = Date().addingTimeInterval(6)
        while Date() < nextDeadline, !next.exists {
            pause(0.05)
        }
        XCTAssertTrue(next.exists, app.debugDescription)
        pause(1.2)
        if next.exists {
            next.tap()
        }

        waitForScore(app, prefix: "Us", score: "0")
        pause(1.6)
        endRecording()
    }

    private func scoreButton(_ app: XCUIApplication, prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func waitForScore(_ app: XCUIApplication, prefix: String, score: String) {
        let plain = "\(prefix) \(score)"
        let serving = "\(prefix) \(score), serving"
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if app.buttons[plain].exists || app.buttons[serving].exists {
                return
            }
            pause(0.05)
        }
        XCTFail("Expected \(plain)\n\(app.debugDescription)")
    }

    private func tapSide(_ app: XCUIApplication, prefix: String) {
        let button = scoreButton(app, prefix: prefix)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if button.exists {
                button.tap()
                return
            }
            pause(0.05)
        }
        XCTFail("Missing \(prefix) control\n\(app.debugDescription)")
    }

    private func dismissHealthSheetIfNeeded() {
        let carousel = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        let close = carousel.buttons["Close"]
        if close.waitForExistence(timeout: 0.8) {
            close.tap()
            pause(0.25)
        }
    }

    private func tapIfExists(_ element: XCUIElement, timeout: TimeInterval) {
        if element.waitForExistence(timeout: timeout) {
            element.tap()
        }
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func beginRecording() {
        writeTimestamp(recordStartedAt)
    }

    private func endRecording() {
        writeTimestamp(recordEndedAt)
    }

    private func writeTimestamp(_ path: String) {
        let value = String(Date().timeIntervalSince1970)
        try? value.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }
}

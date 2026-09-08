import XCTest

/// Drives a short on-watch scoring sequence for the marketing site clip.
/// Run via `website/scripts/record-score-demo.sh`.
final class MarketingDemoTests: XCTestCase {
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

        tapIfExists(app.buttons["Got it"], timeout: 2)

        if app.staticTexts["Who's serving?"].waitForExistence(timeout: 1) {
            app.buttons["Back"].tap()
            pause(0.5)
        }

        if !scoreButton(app, prefix: "Us").waitForExistence(timeout: 1) {
            XCTAssertTrue(
                app.buttons["Start Match"].waitForExistence(timeout: 8),
                app.debugDescription
            )
            app.buttons["Start Match"].tap()
            dismissHealthSheetIfNeeded()
            tapIfExists(app.buttons["Track without workout"], timeout: 2)
            tapIfExists(app.buttons["OK"], timeout: 1)
            dismissHealthSheetIfNeeded()
        }

        if app.buttons["We are serving"].waitForExistence(timeout: 8) {
            pause(0.4)
            app.buttons["We are serving"].tap()
            dismissHealthSheetIfNeeded()
            if app.buttons["We are serving"].waitForExistence(timeout: 1) {
                app.buttons["We are serving"].tap()
            }
        }

        XCTAssertTrue(scoreButton(app, prefix: "Us").waitForExistence(timeout: 8), app.debugDescription)
        pause(0.7)
        tapSide(app, prefix: "Us")
        pause(0.75)
        tapSide(app, prefix: "Us")
        pause(0.75)
        tapSide(app, prefix: "Them")
        pause(0.75)
        tapSide(app, prefix: "Us")
        pause(0.35)
        tapSide(app, prefix: "Us")
        pause(0.9)
        tapSide(app, prefix: "Them")
        pause(0.75)
        tapSide(app, prefix: "Us")
        pause(1.6)
    }

    private func scoreButton(_ app: XCUIApplication, prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func tapSide(_ app: XCUIApplication, prefix: String) {
        let button = scoreButton(app, prefix: prefix)
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing \(prefix) control\n\(app.debugDescription)")
        button.tap()
    }

    private func dismissHealthSheetIfNeeded() {
        let carousel = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        let close = carousel.buttons["Close"]
        if close.waitForExistence(timeout: 2) {
            close.tap()
            pause(0.4)
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
}

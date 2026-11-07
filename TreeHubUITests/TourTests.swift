import XCTest

/// Walks through every screen with sample data so CI can record a video tour.
final class TourTests: XCTestCase {
    let app = XCUIApplication()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = true
        app.launchArguments = ["-demo"]
        app.launch()
    }

    private func pause(_ s: Double) { Thread.sleep(forTimeInterval: s); allowAlerts() }

    private func allowAlerts() {
        for label in ["Allow While Using App", "Allow Once", "Allow", "OK"] {
            let b = springboard.buttons[label]
            if b.exists { b.tap(); return }
        }
    }

    @discardableResult
    private func tap(_ text: String, timeout: Double = 4) -> Bool {
        let pred = NSPredicate(format: "label == %@ OR label CONTAINS %@", text, text)
        let el = app.buttons.matching(pred).firstMatch
        if el.waitForExistence(timeout: timeout) && el.isHittable { el.tap(); return true }
        let t = app.staticTexts.matching(pred).firstMatch
        if t.waitForExistence(timeout: 1) { t.tap(); return true }
        return false
    }

    private func scrollDown(_ n: Int = 1, pauseEach: Double = 1.2) {
        for _ in 0..<n { app.swipeUp(velocity: .slow); pause(pauseEach) }
    }

    private func scrollUp(_ n: Int = 1) {
        for _ in 0..<n { app.swipeDown(velocity: .fast) }
        pause(0.6)
    }

    private func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.exists { b.tap() }
        pause(1)
    }

    func testTour() {
        pause(3)
        // Home
        scrollDown(3)
        scrollUp(3)

        // Log a hug
        tap("Log a tree hug")
        pause(3)
        scrollDown(1)
        pause(1)
        scrollDown(2)
        tap("Barefoot")
        pause(0.8)
        tap("Chill"); pause(0.5)
        tap("Park"); pause(0.5)
        tap("Sober"); pause(0.5)
        tap("Sunset"); pause(1)
        scrollDown(2)
        tap("Save this hug")
        pause(6)          // XP count-up and leaf reveal
        scrollDown(1, pauseEach: 2.5)
        tap("Back to the forest")
        pause(2)

        // Grove
        tap("Grove")
        pause(2.5)
        tap("Grandpa Oak")
        pause(2.5)
        scrollDown(2)
        back()
        let seg = app.segmentedControls.firstMatch
        if seg.exists { seg.buttons.element(boundBy: 1).tap() }
        pause(5)

        // Collection
        tap("Collection")
        pause(2.5)
        scrollDown(2)
        scrollUp(2)
        tap("Leaves")
        pause(3)

        // Track a run
        tap("Track")
        pause(2.5)
        tap("Run")
        pause(1)
        tap("Start Run")
        pause(16)
        tap("Finish")
        pause(1.5)
        tap("Save it")
        pause(4)
        scrollDown(1, pauseEach: 2.5)
        tap("Done")
        pause(2)

        // Back home with everything
        tap("Home")
        pause(3)
    }
}

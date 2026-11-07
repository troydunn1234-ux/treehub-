import XCTest

/// Walks through TrackHub with sample trips so CI can record a video tour.
final class TrackTourTests: XCTestCase {
    let app = XCUIApplication()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = true
        app.launchArguments = ["-demo", "-showIntro"]
        app.launch()
    }

    private func pause(_ s: Double) {
        Thread.sleep(forTimeInterval: s)
        for label in ["Allow While Using App", "Allow Once", "Allow", "OK"] {
            let b = springboard.buttons[label]
            if b.exists { b.tap(); break }
        }
    }

    @discardableResult
    private func tap(_ text: String, timeout: Double = 4) -> Bool {
        let pred = NSPredicate(format: "label == %@ OR label CONTAINS %@", text, text)
        let el = app.buttons.matching(pred).firstMatch
        if el.waitForExistence(timeout: timeout) && el.isHittable { el.tap(); return true }
        return false
    }

    private func tab(_ name: String) {
        let b = app.buttons["tab-\(name)"]
        if b.waitForExistence(timeout: 4) { b.tap() }
        pause(2.5)
    }

    private func scrollDown(_ n: Int, pauseEach: Double = 1.3) {
        for _ in 0..<n { app.swipeUp(velocity: .slow); pause(pauseEach) }
    }

    private func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.exists { b.tap() }
        pause(1)
    }

    private func onboarding() {
        pause(2.5)   // launch animation
        for _ in 0..<3 {
            let c = app.buttons["onboarding-continue"]
            if c.waitForExistence(timeout: 3) { c.tap() }
            pause(2)
        }
        let d = app.buttons["onboarding-done"]
        if d.waitForExistence(timeout: 3) { d.tap() }
        pause(2)
    }

    /// Leave the app for a moment so the Dynamic Island live activity shows.
    private func peekAtDynamicIsland() {
        XCUIDevice.shared.press(.home)
        pause(5)
        app.activate()
        pause(2)
    }

    func testTour() {
        onboarding()
        // Track screen
        scrollDown(2)
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        pause(1)
        // History
        tab("History")
        scrollDown(2)
        tap("Run")
        pause(2)
        tap("All")
        pause(1)
        // Open a trip
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Morning'")).firstMatch
        if first.waitForExistence(timeout: 3) { first.tap() }
        pause(3)
        scrollDown(1, pauseEach: 2)
        back()
        // Stats
        tab("Stats")
        scrollDown(3, pauseEach: 1.8)
        let seg = app.segmentedControls.firstMatch
        if seg.exists { seg.buttons.element(boundBy: 3).tap() }
        pause(2)
        // Record a run
        tab("Track")
        tap("Run")
        pause(1)
        tap("Start Run")
        pause(18)
        peekAtDynamicIsland()
        tap("Finish")
        pause(1.5)
        tap("Save it")
        pause(4)
        if !tap("Done") { app.swipeUp(velocity: .fast); pause(1); tap("Done") }
        pause(2)
        tab("Stats")
        pause(2)
    }
}

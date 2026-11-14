import XCTest

/// The minimized player must open the full player from anywhere on its row
/// except its buttons, and not only while playing. Paused, the title is
/// plain text sized to its words, so the gap between it and the skip button
/// used to ignore taps (the playing marquee stretched to fill it).
final class MiniPlayerTapTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTapBesidePausedTitleOpensFullPlayer() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestPausedMiniPlayer"]
        app.launch()

        let skipBack = app.buttons["Skip back 10 seconds"].firstMatch
        XCTAssertTrue(skipBack.waitForExistence(timeout: 10), "mini player not shown")
        XCTAssertTrue(app.buttons["Play"].firstMatch.exists, "mini player should be paused")

        // The empty space just left of the skip-back button.
        skipBack.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: -40, dy: 0))
            .tap()

        // The full player is always in the view tree, parked off screen,
        // so "exists" proves nothing; it has to be on screen and hittable.
        let minimize = app.buttons["Minimize player"].firstMatch
        let onScreen = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: minimize)
        XCTAssertEqual(XCTWaiter.wait(for: [onScreen], timeout: 5), .completed,
                       "tapping the paused mini player did not open the full player")
    }
}

import XCTest

/// Going back from a book list to Authors must land where you left the
/// list, not at the top. The list used to reload on every appearance and
/// swap itself for a spinner meanwhile, which threw the scroll position away.
final class ListScrollPositionTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testBackFromAuthorKeepsAuthorsScrollPosition() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestLibraryFixture"]
        app.launch()

        let libraryTab = app.buttons["Library"].firstMatch
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 10), "tab bar not shown")
        libraryTab.tap()

        let authorsCard = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Authors'")).firstMatch
        XCTAssertTrue(authorsCard.waitForExistence(timeout: 5), "Authors card not shown")
        authorsCard.tap()

        XCTAssertTrue(app.staticTexts["Author 01"].waitForExistence(timeout: 5), "authors not loaded")

        // Scroll until an author well down the list is on screen.
        // Lazy rows don't exist until scrolled near, and isHittable on a
        // missing element kills the runner, so check exists first.
        let target = app.staticTexts["Author 30"]
        for _ in 0..<15 where !(target.exists && target.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(target.exists && target.isHittable, "could not scroll to Author 30")

        target.tap()
        XCTAssertTrue(app.staticTexts["Book by Author 30"].waitForExistence(timeout: 5), "author's books not shown")

        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Back on Authors: still scrolled. The old reload put the top of the
        // list back on screen within a moment, so watch for that.
        XCTAssertTrue(app.staticTexts["Author 30"].waitForExistence(timeout: 5), "not back on Authors")
        let jumpedToTop = expectation(for: NSPredicate(format: "exists == true AND isHittable == true"),
                                      evaluatedWith: app.staticTexts["Author 01"])
        XCTAssertEqual(XCTWaiter.wait(for: [jumpedToTop], timeout: 3), .timedOut,
                       "Authors list jumped back to the top")
        let kept = app.staticTexts["Author 30"]
        XCTAssertTrue(kept.exists && kept.isHittable, "Authors list did not keep its scroll position")
    }
}
